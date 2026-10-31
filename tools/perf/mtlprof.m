// mtlprof: where does a game's GPU time go? Interposes the public Metal API inside the game process (no
// change to D3DMetal or any Apple binary) and attaches Metal's stage-boundary timestamp counters to every
// render, compute and blit pass. After NECTARINE_MTLPROF_SKIP frames it reports every NECTARINE_MTLPROF_FRAMES
// frames: passes, draws and GPU time per frame, and the pass kinds ranked by GPU time, with attachment sizes,
// load/store actions and estimated attachment traffic.
//
//   clang -arch x86_64 -fobjc-arc -dynamiclib -framework Foundation -framework Metal -framework QuartzCore \
//         mtlprof.m -o mtlprof.dylib
//   DYLD_INSERT_LIBRARIES=mtlprof.dylib NECTARINE_MTLPROF_EXE="Game.exe" NECTARINE_MTLPROF_OUT=/tmp/prof.txt
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <libproc.h>
#include <mach/mach_time.h>
#include <os/lock.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define SLOTS 4096                     /* samples per counter buffer (Metal caps a buffer at 32 KB) */
#define NBUF 16
#define RING (SLOTS * NBUF)
typedef struct Pass {
    char sig[256];
    char kind;                       /* 'R' render, 'C' compute, 'B' blit */
    double traffic_mb;
    unsigned draws, icb_execs, dispatches, sample;
    unsigned set_tex, set_buf, use_res, use_heap;
    void *att[10]; unsigned natt;            /* render attachments (texture pointers) */
    void *tex[32]; unsigned ntex;            /* textures bound or declared with useResource */
    BOOL tex_overflow;
    struct Pass *next;
} Pass;
typedef struct { Pass *head; } CBState;

static id<MTLCounterSampleBuffer> g_bufs[NBUF];
#define g_samples g_bufs[0]
static atomic_uint g_ring, g_frames;
static double g_gpu_to_ns = 1.0;
static os_unfair_lock g_lock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSMutableArray *> *g_agg;
static double g_cb_gpu_ns;
static unsigned g_seq_rcr, g_seq_rcr_indep, g_seq_rcr_heap, g_bind[4];
static unsigned g_cbs, g_passes[3], g_draws, g_icb, g_disp, g_window_start, g_skip = 600, g_window = 300;
static FILE *g_out;
static __thread Pass *t_pass;
static const void *kCBKey = &kCBKey;
static BOOL g_installed, g_exp_nodepthstore;

static double bytes_per_pixel(MTLPixelFormat f)
{
    switch (f) {
    case MTLPixelFormatRGBA16Float: case MTLPixelFormatRG32Float: case MTLPixelFormatRGBA16Unorm: return 8;
    case MTLPixelFormatRGBA32Float: return 16;
    case MTLPixelFormatR8Unorm: case MTLPixelFormatStencil8: return 1;
    case MTLPixelFormatRG8Unorm: case MTLPixelFormatR16Float: case MTLPixelFormatDepth16Unorm: return 2;
    case MTLPixelFormatDepth32Float_Stencil8: return 5;
    default: return 4;
    }
}
static const char *load_name(MTLLoadAction a) { return a == MTLLoadActionLoad ? "L" : a == MTLLoadActionClear ? "C" : "-"; }
static const char *store_name(MTLStoreAction a)
{
    return (a == MTLStoreActionStore || a == MTLStoreActionStoreAndMultisampleResolve) ? "S" : a == MTLStoreActionMultisampleResolve ? "R" : "-";
}
static void note_tex(Pass *p, id t)
{
    if (!p || !t) return;
    void *k = (__bridge void *)t;
    for (unsigned i = 0; i < p->ntex; i++) if (p->tex[i] == k) return;
    if (p->ntex < 32) p->tex[p->ntex++] = k; else p->tex_overflow = YES;
}
static void describe_attachment(MTLRenderPassAttachmentDescriptor *a, const char *tag, Pass *p)
{
    id<MTLTexture> t = a.texture;
    if (!t) return;
    if (p->natt < 10) p->att[p->natt++] = (__bridge void *)t;
    double bytes = (double)t.width * t.height * bytes_per_pixel(t.pixelFormat) * MAX(1, (int)t.sampleCount);
    if (a.loadAction == MTLLoadActionLoad) p->traffic_mb += bytes / 1e6;
    if (a.storeAction == MTLStoreActionStore || a.storeAction == MTLStoreActionStoreAndMultisampleResolve) p->traffic_mb += bytes / 1e6;
    char tmp[96];
    snprintf(tmp, sizeof(tmp), " %s%lux%lu/f%lu%s/%s%s", tag, (unsigned long)t.width, (unsigned long)t.height,
             (unsigned long)t.pixelFormat, t.sampleCount > 1 ? "/ms" : "", load_name(a.loadAction), store_name(a.storeAction));
    strncat(p->sig, tmp, sizeof(p->sig) - strlen(p->sig) - 1);
}
static unsigned take_samples(unsigned n)
{
    unsigned i;
    do i = atomic_fetch_add(&g_ring, n) % RING; while (i % SLOTS + n > SLOTS);   /* never straddle two buffers */
    return i;
}
static CBState *cb_state(id cb)
{
    NSValue *v = objc_getAssociatedObject(cb, kCBKey);
    if (v) return v.pointerValue;
    CBState *s = calloc(1, sizeof(*s));
    objc_setAssociatedObject(cb, kCBKey, [NSValue valueWithPointer:s], OBJC_ASSOCIATION_RETAIN);
    return s;
}
static Pass *new_pass(id cb, char kind)
{
    Pass *p = calloc(1, sizeof(*p));
    p->kind = kind; p->sample = UINT32_MAX; p->sig[0] = kind; p->sig[1] = 0;
    CBState *s = cb_state(cb);
    os_unfair_lock_lock(&g_lock); p->next = s->head; s->head = p; os_unfair_lock_unlock(&g_lock);
    t_pass = p;
    return p;
}
static BOOL sampling(void) { return g_samples && atomic_load(&g_frames) >= g_skip; }

static void reset_window(void)
{
    [g_agg removeAllObjects]; g_cb_gpu_ns = 0; g_cbs = 0; memset(g_passes, 0, sizeof(g_passes)); g_draws = g_icb = g_disp = 0;
    g_seq_rcr = g_seq_rcr_indep = g_seq_rcr_heap = 0; memset(g_bind, 0, sizeof(g_bind));
}
static void write_report(unsigned frames)
{
    fprintf(g_out, "== %u frames: %.2f cmdbufs/frame, GPU (sum of command buffers) %.2f ms/frame; per frame: %.1f render, "
            "%.1f compute, %.1f blit passes, %.0f draws, %.1f ICB executes, %.0f dispatches\n", frames, (double)g_cbs / frames,
            g_cb_gpu_ns / frames / 1e6, (double)g_passes[0] / frames, (double)g_passes[1] / frames, (double)g_passes[2] / frames,
            (double)g_draws / frames, (double)g_icb / frames, (double)g_disp / frames);
    NSArray *keys = [g_agg keysSortedByValueUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) { return [b[1] compare:a[1]]; }];
    double total = 0, traffic = 0;
    for (NSString *k in keys) { total += [g_agg[k][1] doubleValue]; traffic += [g_agg[k][2] doubleValue]; }
    fprintf(g_out, "   bindings/frame: setTexture %.0f, setBuffer %.0f, useResource %.0f, useHeap %.0f\n"
            "   render->compute->render with the same attachments: %.1f/frame; compute touches none of them: %.1f; "
            "compute used useHeap or too many textures (unknown): %.1f\n",
            (double)g_bind[0] / frames, (double)g_bind[1] / frames, (double)g_bind[2] / frames, (double)g_bind[3] / frames,
            (double)g_seq_rcr / frames, (double)g_seq_rcr_indep / frames, (double)g_seq_rcr_heap / frames);
    fprintf(g_out, "   pass GPU spans %.2f ms/frame (passes overlap on the GPU), attachment traffic %.0f MB/frame\n",
            total / frames / 1e6, traffic / frames);
    fprintf(g_out, "   %%time  ms/frame  passes/fr  ms/pass  attMB/fr  draws/p  icb/p  disp/p  kind + attachments (WxH/format/load/store)\n");
    int shown = 0;
    for (NSString *k in keys) {
        NSArray *v = g_agg[k]; double c = [v[0] doubleValue], ns = [v[1] doubleValue];
        fprintf(g_out, "   %5.1f  %8.3f  %9.2f  %7.3f  %8.1f  %7.1f  %5.1f  %6.1f  %s\n", 100 * ns / MAX(total, 1), ns / frames / 1e6,
                c / frames, ns / c / 1e6, [v[2] doubleValue] / frames, [v[3] doubleValue] / c, [v[4] doubleValue] / c,
                [v[5] doubleValue] / c, k.UTF8String);
        if (++shown == 30) break;
    }
    fflush(g_out);
}

static void completed(id<MTLCommandBuffer> cb)
{
    CBState *s = cb_state(cb);
    unsigned frames = atomic_load(&g_frames);
    BOOL counting = frames >= g_skip;
    os_unfair_lock_lock(&g_lock);
    Pass *p = s->head, *rev = NULL; s->head = NULL;
    while (p) { Pass *n = p->next; p->next = rev; rev = p; p = n; }   /* encode order */
    p = rev;
    if (counting) {
        for (Pass *a = p; a && a->next && a->next->next; a = a->next) {
            Pass *c = a->next, *b = c->next;
            if (a->kind != 'R' || c->kind != 'C' || b->kind != 'R' || !a->natt || a->natt != b->natt) continue;
            if (memcmp(a->att, b->att, a->natt * sizeof(void *))) continue;
            g_seq_rcr++;
            if (c->use_heap || c->tex_overflow) { g_seq_rcr_heap++; continue; }
            BOOL touch = NO;
            for (unsigned i = 0; i < c->ntex && !touch; i++)
                for (unsigned j = 0; j < a->natt; j++) if (c->tex[i] == a->att[j]) touch = YES;
            if (!touch) g_seq_rcr_indep++;
        }
    }
    if (counting) { g_cbs++; g_cb_gpu_ns += (cb.GPUEndTime - cb.GPUStartTime) * 1e9; }
    while (p) {
        if (counting) {
            double ns = 0;
            if (p->sample != UINT32_MAX) {
                unsigned n = p->kind == 'R' ? 4 : 2;
                NSData *data = [g_bufs[p->sample / SLOTS] resolveCounterRange:NSMakeRange(p->sample % SLOTS, n)];
                const MTLCounterResultTimestamp *ts = data.bytes;
                uint64_t lo = UINT64_MAX, hi = 0;
                for (unsigned i = 0; data && i < data.length / sizeof(*ts); i++) {
                    uint64_t t = ts[i].timestamp;
                    if (t == MTLCounterErrorValue || !t) continue;
                    if (t < lo) lo = t;
                    if (t > hi) hi = t;
                }
                if (hi > lo) ns = (double)(hi - lo) * g_gpu_to_ns;
            }
            NSString *k = [NSString stringWithUTF8String:p->sig];
            NSMutableArray *v = g_agg[k];
            if (!v) { v = [@[@0, @0.0, @0.0, @0, @0, @0] mutableCopy]; g_agg[k] = v; }
            v[0] = @([v[0] unsignedIntValue] + 1); v[1] = @([v[1] doubleValue] + ns);
            v[2] = @([v[2] doubleValue] + p->traffic_mb); v[3] = @([v[3] unsignedIntValue] + p->draws);
            v[4] = @([v[4] unsignedIntValue] + p->icb_execs); v[5] = @([v[5] unsignedIntValue] + p->dispatches);
            g_passes[p->kind == 'R' ? 0 : p->kind == 'C' ? 1 : 2]++;
            g_draws += p->draws; g_icb += p->icb_execs; g_disp += p->dispatches;
            g_bind[0] += p->set_tex; g_bind[1] += p->set_buf; g_bind[2] += p->use_res; g_bind[3] += p->use_heap;
        }
        Pass *n = p->next; free(p); p = n;
    }
    if (counting && frames - g_window_start >= g_window) {
        if (g_window_start >= g_skip) write_report(frames - g_window_start);
        reset_window();
        g_window_start = frames;
    }
    os_unfair_lock_unlock(&g_lock);
}

static IMP swap(Class c, const char *name, id block)
{
    Method m = class_getInstanceMethod(c, sel_registerName(name));
    if (!m) { fprintf(g_out, "mtlprof: %s has no %s\n", class_getName(c), name); return NULL; }
    return method_setImplementation(m, imp_implementationWithBlock(block));
}

/* originals */
static IMP o_render, o_compute, o_compute_type, o_compute_desc, o_blit, o_blit_desc, o_commit;
static IMP o_draw, o_draw_inst, o_draw_idx, o_draw_idx_base, o_draw_indirect, o_draw_idx_indirect, o_exec_icb, o_exec_icb_ind;
static IMP o_disp_tg, o_disp_th, o_disp_ind, o_cexec_icb;

static id make_compute(id cb, MTLDispatchType type)
{
    Pass *p = new_pass(cb, 'C');
    MTLComputePassDescriptor *d = [MTLComputePassDescriptor computePassDescriptor];
    d.dispatchType = type;
    if (sampling()) {
        unsigned i = take_samples(2); p->sample = i;
        d.sampleBufferAttachments[0].sampleBuffer = g_bufs[i / SLOTS]; i %= SLOTS;
        d.sampleBufferAttachments[0].startOfEncoderSampleIndex = i;
        d.sampleBufferAttachments[0].endOfEncoderSampleIndex = i + 1;
    }
    return ((id (*)(id, SEL, id))o_compute_desc)(cb, sel_registerName("computeCommandEncoderWithDescriptor:"), d);
}
static id make_blit(id cb)
{
    Pass *p = new_pass(cb, 'B');
    MTLBlitPassDescriptor *d = [MTLBlitPassDescriptor blitPassDescriptor];
    if (sampling()) {
        unsigned i = take_samples(2); p->sample = i;
        d.sampleBufferAttachments[0].sampleBuffer = g_bufs[i / SLOTS]; i %= SLOTS;
        d.sampleBufferAttachments[0].startOfEncoderSampleIndex = i;
        d.sampleBufferAttachments[0].endOfEncoderSampleIndex = i + 1;
    }
    return ((id (*)(id, SEL, id))o_blit_desc)(cb, sel_registerName("blitCommandEncoderWithDescriptor:"), d);
}

static void install_hooks(id<MTLDevice> dev)
{
    id<MTLCommandQueue> q = [dev newCommandQueue];
    id<MTLCommandBuffer> cb = [q commandBuffer];
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:16 height:16 mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget; td.storageMode = MTLStorageModePrivate;
    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
    rp.colorAttachments[0].texture = [dev newTextureWithDescriptor:td];
    id<MTLRenderCommandEncoder> re = [cb renderCommandEncoderWithDescriptor:rp]; Class REnc = [re class]; [re endEncoding];
    id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder]; Class CEnc = [ce class]; [ce endEncoding];
    id<MTLBlitCommandEncoder> be = [cb blitCommandEncoder]; Class BEnc = [be class]; [be endEncoding];
    Class CB = [cb class];

    MTLCounterSampleBufferDescriptor *sd = [MTLCounterSampleBufferDescriptor new];
    for (id<MTLCounterSet> set in dev.counterSets) if ([set.name isEqualToString:MTLCommonCounterSetTimestamp]) sd.counterSet = set;
    sd.sampleCount = SLOTS; sd.storageMode = MTLStorageModeShared;
    BOOL stage = [dev supportsCounterSampling:MTLCounterSamplingPointAtStageBoundary];
    NSError *err = nil;
    if (sd.counterSet && stage) for (int b = 0; b < NBUF; b++) g_bufs[b] = [dev newCounterSampleBufferWithDescriptor:sd error:&err];
    MTLTimestamp c0, g0, c1, g1;
    [dev sampleTimestamps:&c0 gpuTimestamp:&g0]; usleep(200000); [dev sampleTimestamps:&c1 gpuTimestamp:&g1];
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    if (g1 > g0) g_gpu_to_ns = (double)(c1 - c0) * tb.numer / tb.denom / (double)(g1 - g0);
    fprintf(g_out, "mtlprof: device %s; stage-boundary timestamps %s%s; gpu tick %.3f ns; classes %s %s %s %s\n",
            dev.name.UTF8String, g_samples ? "yes" : "NO (no pass timing)", err ? err.localizedDescription.UTF8String : "",
            g_gpu_to_ns, class_getName(CB), class_getName(REnc), class_getName(CEnc), class_getName(BEnc));
    fflush(g_out);

    o_render = swap(CB, "renderCommandEncoderWithDescriptor:", ^id(id self, MTLRenderPassDescriptor *d) {
        Pass *p = new_pass(self, 'R');
        /* NECTARINE_MTLPROF_EXPERIMENT=nodepthstore: measurement only, unsafe. On passes that load both colour
         * and depth (mid-frame passes, not the ones that clear), skip writing depth/stencil back. */
        if (g_exp_nodepthstore && d.colorAttachments[0].texture && d.colorAttachments[0].loadAction == MTLLoadActionLoad
            && d.depthAttachment.texture && d.depthAttachment.loadAction == MTLLoadActionLoad) {
            d.depthAttachment.storeAction = MTLStoreActionDontCare;
            if (d.stencilAttachment.texture) d.stencilAttachment.storeAction = MTLStoreActionDontCare;
            strncat(p->sig, " [exp]", sizeof(p->sig) - strlen(p->sig) - 1);
        }
        for (int i = 0; i < 8; i++) describe_attachment(d.colorAttachments[i], "c", p);
        describe_attachment(d.depthAttachment, "d", p);
        if (d.stencilAttachment.texture && d.stencilAttachment.texture == d.depthAttachment.texture) {
            char tmp[16];   /* combined depth/stencil: one texture, traffic already counted with depth */
            snprintf(tmp, sizeof(tmp), " s=d/%s%s", load_name(d.stencilAttachment.loadAction), store_name(d.stencilAttachment.storeAction));
            strncat(p->sig, tmp, sizeof(p->sig) - strlen(p->sig) - 1);
        } else describe_attachment(d.stencilAttachment, "s", p);
        if (sampling()) {
            unsigned i = take_samples(4); p->sample = i;
            MTLRenderPassSampleBufferAttachmentDescriptor *a = d.sampleBufferAttachments[0];
            a.sampleBuffer = g_bufs[i / SLOTS]; i %= SLOTS;
            a.startOfVertexSampleIndex = i; a.endOfVertexSampleIndex = i + 1;
            a.startOfFragmentSampleIndex = i + 2; a.endOfFragmentSampleIndex = i + 3;
        }
        return ((id (*)(id, SEL, id))o_render)(self, sel_registerName("renderCommandEncoderWithDescriptor:"), d);
    });
    o_compute_desc = swap(CB, "computeCommandEncoderWithDescriptor:", ^id(id self, MTLComputePassDescriptor *d) {
        Pass *p = new_pass(self, 'C');
        if (sampling()) {
            unsigned i = take_samples(2); p->sample = i;
            d.sampleBufferAttachments[0].sampleBuffer = g_bufs[i / SLOTS]; i %= SLOTS;
            d.sampleBufferAttachments[0].startOfEncoderSampleIndex = i;
            d.sampleBufferAttachments[0].endOfEncoderSampleIndex = i + 1;
        }
        return ((id (*)(id, SEL, id))o_compute_desc)(self, sel_registerName("computeCommandEncoderWithDescriptor:"), d);
    });
    o_compute = swap(CB, "computeCommandEncoder", ^id(id self) { return make_compute(self, MTLDispatchTypeSerial); });
    o_compute_type = swap(CB, "computeCommandEncoderWithDispatchType:", ^id(id self, MTLDispatchType t) { return make_compute(self, t); });
    o_blit_desc = swap(CB, "blitCommandEncoderWithDescriptor:", ^id(id self, MTLBlitPassDescriptor *d) {
        Pass *p = new_pass(self, 'B');
        if (sampling()) {
            unsigned i = take_samples(2); p->sample = i;
            d.sampleBufferAttachments[0].sampleBuffer = g_bufs[i / SLOTS]; i %= SLOTS;
            d.sampleBufferAttachments[0].startOfEncoderSampleIndex = i;
            d.sampleBufferAttachments[0].endOfEncoderSampleIndex = i + 1;
        }
        return ((id (*)(id, SEL, id))o_blit_desc)(self, sel_registerName("blitCommandEncoderWithDescriptor:"), d);
    });
    o_blit = swap(CB, "blitCommandEncoder", ^id(id self) { return make_blit(self); });
    o_commit = swap(CB, "commit", ^void(id self) {
        if (cb_state(self)->head)
            [(id<MTLCommandBuffer>)self addCompletedHandler:^(id<MTLCommandBuffer> done) { completed(done); }];
        ((void (*)(id, SEL))o_commit)(self, sel_registerName("commit"));
    });

    /* draw / dispatch counting on the encoder that is being recorded on this thread */
    o_draw = swap(REnc, "drawPrimitives:vertexStart:vertexCount:", ^void(id self, MTLPrimitiveType t, NSUInteger s, NSUInteger c) {
        if (t_pass) t_pass->draws++;
        ((void (*)(id, SEL, MTLPrimitiveType, NSUInteger, NSUInteger))o_draw)(self, sel_registerName("drawPrimitives:vertexStart:vertexCount:"), t, s, c);
    });
    o_draw_inst = swap(REnc, "drawPrimitives:vertexStart:vertexCount:instanceCount:baseInstance:",
                       ^void(id self, MTLPrimitiveType t, NSUInteger s, NSUInteger c, NSUInteger i, NSUInteger b) {
        if (t_pass) t_pass->draws++;
        ((void (*)(id, SEL, MTLPrimitiveType, NSUInteger, NSUInteger, NSUInteger, NSUInteger))o_draw_inst)(self,
            sel_registerName("drawPrimitives:vertexStart:vertexCount:instanceCount:baseInstance:"), t, s, c, i, b);
    });
    o_draw_idx = swap(REnc, "drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:",
                      ^void(id self, MTLPrimitiveType t, NSUInteger c, MTLIndexType it, id buf, NSUInteger off, NSUInteger inst) {
        if (t_pass) t_pass->draws++;
        ((void (*)(id, SEL, MTLPrimitiveType, NSUInteger, MTLIndexType, id, NSUInteger, NSUInteger))o_draw_idx)(self,
            sel_registerName("drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:"), t, c, it, buf, off, inst);
    });
    o_draw_idx_base = swap(REnc, "drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:baseVertex:baseInstance:",
                           ^void(id self, MTLPrimitiveType t, NSUInteger c, MTLIndexType it, id buf, NSUInteger off, NSUInteger inst, NSInteger bv, NSUInteger bi) {
        if (t_pass) t_pass->draws++;
        ((void (*)(id, SEL, MTLPrimitiveType, NSUInteger, MTLIndexType, id, NSUInteger, NSUInteger, NSInteger, NSUInteger))o_draw_idx_base)(self,
            sel_registerName("drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:baseVertex:baseInstance:"),
            t, c, it, buf, off, inst, bv, bi);
    });
    o_draw_indirect = swap(REnc, "drawPrimitives:indirectBuffer:indirectBufferOffset:", ^void(id self, MTLPrimitiveType t, id b, NSUInteger o) {
        if (t_pass) t_pass->draws++;
        ((void (*)(id, SEL, MTLPrimitiveType, id, NSUInteger))o_draw_indirect)(self, sel_registerName("drawPrimitives:indirectBuffer:indirectBufferOffset:"), t, b, o);
    });
    o_draw_idx_indirect = swap(REnc, "drawIndexedPrimitives:indexType:indexBuffer:indexBufferOffset:indirectBuffer:indirectBufferOffset:",
                               ^void(id self, MTLPrimitiveType t, MTLIndexType it, id ib, NSUInteger io, id b, NSUInteger o) {
        if (t_pass) t_pass->draws++;
        ((void (*)(id, SEL, MTLPrimitiveType, MTLIndexType, id, NSUInteger, id, NSUInteger))o_draw_idx_indirect)(self,
            sel_registerName("drawIndexedPrimitives:indexType:indexBuffer:indexBufferOffset:indirectBuffer:indirectBufferOffset:"), t, it, ib, io, b, o);
    });
    o_exec_icb = swap(REnc, "executeCommandsInBuffer:withRange:", ^void(id self, id icb, NSRange r) {
        if (t_pass) { t_pass->icb_execs++; t_pass->draws += (unsigned)r.length; }
        ((void (*)(id, SEL, id, NSRange))o_exec_icb)(self, sel_registerName("executeCommandsInBuffer:withRange:"), icb, r);
    });
    o_exec_icb_ind = swap(REnc, "executeCommandsInBuffer:indirectBuffer:indirectBufferOffset:", ^void(id self, id icb, id b, NSUInteger o) {
        if (t_pass) t_pass->icb_execs++;
        ((void (*)(id, SEL, id, id, NSUInteger))o_exec_icb_ind)(self, sel_registerName("executeCommandsInBuffer:indirectBuffer:indirectBufferOffset:"), icb, b, o);
    });
    o_disp_tg = swap(CEnc, "dispatchThreadgroups:threadsPerThreadgroup:", ^void(id self, MTLSize a, MTLSize b) {
        if (t_pass) t_pass->dispatches++;
        ((void (*)(id, SEL, MTLSize, MTLSize))o_disp_tg)(self, sel_registerName("dispatchThreadgroups:threadsPerThreadgroup:"), a, b);
    });
    o_disp_th = swap(CEnc, "dispatchThreads:threadsPerThreadgroup:", ^void(id self, MTLSize a, MTLSize b) {
        if (t_pass) t_pass->dispatches++;
        ((void (*)(id, SEL, MTLSize, MTLSize))o_disp_th)(self, sel_registerName("dispatchThreads:threadsPerThreadgroup:"), a, b);
    });
    o_disp_ind = swap(CEnc, "dispatchThreadgroupsWithIndirectBuffer:indirectBufferOffset:threadsPerThreadgroup:", ^void(id self, id b, NSUInteger o, MTLSize t) {
        if (t_pass) t_pass->dispatches++;
        ((void (*)(id, SEL, id, NSUInteger, MTLSize))o_disp_ind)(self, sel_registerName("dispatchThreadgroupsWithIndirectBuffer:indirectBufferOffset:threadsPerThreadgroup:"), b, o, t);
    });
    o_cexec_icb = swap(CEnc, "executeCommandsInBuffer:withRange:", ^void(id self, id icb, NSRange r) {
        if (t_pass) { t_pass->icb_execs++; t_pass->dispatches += (unsigned)r.length; }
        ((void (*)(id, SEL, id, NSRange))o_cexec_icb)(self, sel_registerName("executeCommandsInBuffer:withRange:"), icb, r);
    });
    for (int k = 0; k < 2; k++) {
        Class E = k ? CEnc : REnc;
        const char *tex_sels[] = { "setTexture:atIndex:", "setVertexTexture:atIndex:", "setFragmentTexture:atIndex:" };
        for (int t = 0; t < 3; t++) {
            Method m = class_getInstanceMethod(E, sel_registerName(tex_sels[t]));
            if (!m) continue;
            __block IMP o = method_getImplementation(m); SEL sl = sel_registerName(tex_sels[t]);
            method_setImplementation(m, imp_implementationWithBlock(^void(id self, id tx, NSUInteger i) {
                if (t_pass) { t_pass->set_tex++; note_tex(t_pass, tx); }
                ((void (*)(id, SEL, id, NSUInteger))o)(self, sl, tx, i);
            }));
        }
        const char *buf_sels[] = { "setBuffer:offset:atIndex:", "setVertexBuffer:offset:atIndex:", "setFragmentBuffer:offset:atIndex:" };
        for (int t = 0; t < 3; t++) {
            Method m = class_getInstanceMethod(E, sel_registerName(buf_sels[t]));
            if (!m) continue;
            __block IMP o = method_getImplementation(m); SEL sl = sel_registerName(buf_sels[t]);
            method_setImplementation(m, imp_implementationWithBlock(^void(id self, id b, NSUInteger off, NSUInteger i) {
                if (t_pass) t_pass->set_buf++;
                ((void (*)(id, SEL, id, NSUInteger, NSUInteger))o)(self, sl, b, off, i);
            }));
        }
        const char *res1 = k ? "useResource:usage:" : "useResource:usage:stages:";
        Method m = class_getInstanceMethod(E, sel_registerName(res1));
        if (m) {
            __block IMP o = method_getImplementation(m); SEL sl = sel_registerName(res1); BOOL stages = !k;
            method_setImplementation(m, imp_implementationWithBlock(^void(id self, id r, MTLResourceUsage u, MTLRenderStages st) {
                if (t_pass) { t_pass->use_res++; if ([r conformsToProtocol:@protocol(MTLTexture)]) note_tex(t_pass, r); }
                if (stages) ((void (*)(id, SEL, id, MTLResourceUsage, MTLRenderStages))o)(self, sl, r, u, st);
                else ((void (*)(id, SEL, id, MTLResourceUsage))o)(self, sl, r, u);
            }));
        }
        const char *resn = k ? "useResources:count:usage:" : "useResources:count:usage:stages:";
        m = class_getInstanceMethod(E, sel_registerName(resn));
        if (m) {
            __block IMP o = method_getImplementation(m); SEL sl = sel_registerName(resn); BOOL stages = !k;
            method_setImplementation(m, imp_implementationWithBlock(^void(id self, const id __unsafe_unretained *rs, NSUInteger n, MTLResourceUsage u, MTLRenderStages st) {
                if (t_pass) { t_pass->use_res += (unsigned)n;
                    for (NSUInteger i = 0; i < n; i++) if ([rs[i] conformsToProtocol:@protocol(MTLTexture)]) note_tex(t_pass, rs[i]); }
                if (stages) ((void (*)(id, SEL, const id __unsafe_unretained *, NSUInteger, MTLResourceUsage, MTLRenderStages))o)(self, sl, rs, n, u, st);
                else ((void (*)(id, SEL, const id __unsafe_unretained *, NSUInteger, MTLResourceUsage))o)(self, sl, rs, n, u);
            }));
        }
        const char *heap1 = k ? "useHeap:" : "useHeap:stages:";
        m = class_getInstanceMethod(E, sel_registerName(heap1));
        if (m) {
            __block IMP o = method_getImplementation(m); SEL sl = sel_registerName(heap1); BOOL stages = !k;
            method_setImplementation(m, imp_implementationWithBlock(^void(id self, id h, MTLRenderStages st) {
                if (t_pass) t_pass->use_heap++;
                if (stages) ((void (*)(id, SEL, id, MTLRenderStages))o)(self, sl, h, st);
                else ((void (*)(id, SEL, id))o)(self, sl, h);
            }));
        }
        const char *heapn = k ? "useHeaps:count:" : "useHeaps:count:stages:";
        m = class_getInstanceMethod(E, sel_registerName(heapn));
        if (m) {
            __block IMP o = method_getImplementation(m); SEL sl = sel_registerName(heapn); BOOL stages = !k;
            method_setImplementation(m, imp_implementationWithBlock(^void(id self, const id __unsafe_unretained *hs, NSUInteger n, MTLRenderStages st) {
                if (t_pass) t_pass->use_heap += (unsigned)n;
                if (stages) ((void (*)(id, SEL, const id __unsafe_unretained *, NSUInteger, MTLRenderStages))o)(self, sl, hs, n, st);
                else ((void (*)(id, SEL, const id __unsafe_unretained *, NSUInteger))o)(self, sl, hs, n);
            }));
        }
    }
    (void)o_compute; (void)o_compute_type; (void)o_blit;
}

static int g_state;   /* 0 undecided, 1 profiling, -1 not the target process */
static const char *g_want, *g_outpath;

/* Decide on the first presented frame: Wine renames the process to the game's exe only after start-up. */
static BOOL decide(CAMetalLayer *layer)
{
    if (g_state) return g_state > 0;
    char name[256] = "";
    proc_name(getpid(), name, sizeof(name));
    if (!name[0] || (!strcasestr(name, g_want) && !strcasestr(g_want, name)) || !strcmp(name, "wine")) { g_state = -1; return NO; }
    g_out = fopen(g_outpath, "a");
    if (!g_out) { g_state = -1; return NO; }
    fprintf(g_out, "mtlprof: attached to %s (pid %d)\n", name, getpid()); fflush(g_out);
    g_agg = [NSMutableDictionary new];
    install_hooks(layer.device ?: MTLCreateSystemDefaultDevice());
    g_state = 1;
    return YES;
}

__attribute__((constructor)) static void mtlprof_init(void)
{
    g_want = getenv("NECTARINE_MTLPROF_EXE"); g_outpath = getenv("NECTARINE_MTLPROF_OUT");
    if (!g_want || !g_outpath) return;
    if (getenv("NECTARINE_MTLPROF_FRAMES")) g_window = (unsigned)atoi(getenv("NECTARINE_MTLPROF_FRAMES"));
    { const char *e = getenv("NECTARINE_MTLPROF_EXPERIMENT"); g_exp_nodepthstore = e && !strcmp(e, "nodepthstore"); }
    if (getenv("NECTARINE_MTLPROF_SKIP")) g_skip = (unsigned)atoi(getenv("NECTARINE_MTLPROF_SKIP"));
    Method m = class_getInstanceMethod([CAMetalLayer class], @selector(nextDrawable));
    __block IMP orig = method_getImplementation(m);
    method_setImplementation(m, imp_implementationWithBlock(^id(CAMetalLayer *self) {
        if (g_state >= 0) {
            os_unfair_lock_lock(&g_lock);
            BOOL on = decide(self);
            os_unfair_lock_unlock(&g_lock);
            if (on) atomic_fetch_add(&g_frames, 1);
        }
        return ((id (*)(id, SEL))orig)(self, @selector(nextDrawable));
    }));
}
