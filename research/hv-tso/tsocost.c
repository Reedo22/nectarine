// tsocost: same guest loops with TSO off vs on (one vCPU, MMU on, cacheable memory).
#include <Hypervisor/Hypervisor.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
extern char g_copy[], g_copy_end[], g_ptr[], g_ptr_end[], g_copy_rel[], g_copy_rel_end[], g_ptr_rel[], g_ptr_rel_end[];
#define MEM (64u << 20)
static uint8_t *mem;
static double run(uint64_t pc, int tso, uint64_t x0, uint64_t x1, uint64_t x2, uint64_t x3)
{
    hv_vcpu_t v; hv_vcpu_exit_t *e; hv_vcpu_create(&v, &e, NULL);
    hv_vcpu_set_sys_reg(v, HV_SYS_REG_MAIR_EL1, 0xff);
    hv_vcpu_set_sys_reg(v, HV_SYS_REG_TCR_EL1, 32 | (1u << 8) | (1u << 10) | (3u << 12) | (1u << 23) | (1ull << 32));
    hv_vcpu_set_sys_reg(v, HV_SYS_REG_TTBR0_EL1, 0x1000);
    hv_vcpu_set_sys_reg(v, HV_SYS_REG_SCTLR_EL1, 0x30d00800 | 1 | (1 << 2) | (1 << 12));
    hv_vcpu_set_sys_reg(v, HV_SYS_REG_ACTLR_EL1, tso ? 2 : 0);
    hv_vcpu_set_reg(v, HV_REG_CPSR, 0x3c5); hv_vcpu_set_reg(v, HV_REG_PC, pc);
    hv_vcpu_set_reg(v, HV_REG_X0, x0); hv_vcpu_set_reg(v, HV_REG_X1, x1); hv_vcpu_set_reg(v, HV_REG_X2, x2); hv_vcpu_set_reg(v, HV_REG_X3, x3);
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    uint64_t t = mach_absolute_time(); hv_vcpu_run(v); t = mach_absolute_time() - t;
    hv_vcpu_destroy(v); return (double)t * tb.numer / tb.denom / 1e9;
}
int main(void)
{
    hv_vm_create(NULL);
    mem = mmap(NULL, MEM, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    hv_vm_map(mem, 0, MEM, HV_MEMORY_READ | HV_MEMORY_WRITE | HV_MEMORY_EXEC);
    ((uint64_t *)(mem + 0x1000))[0] = (1 << 10) | (3 << 8) | 1;
    memcpy(mem + 0x2000, g_copy, g_copy_end - g_copy); memcpy(mem + 0x3000, g_ptr, g_ptr_end - g_ptr);
    memcpy(mem + 0x4000, g_copy_rel, g_copy_rel_end - g_copy_rel); memcpy(mem + 0x5000, g_ptr_rel, g_ptr_rel_end - g_ptr_rel);
    /* pointer-chase table: 1 MB of 16-byte nodes in a random cycle (L2-resident) */
    uint64_t base = 0x400000, n = (1u << 20) / 16; uint32_t *perm = malloc(n * 4);
    for (uint64_t i = 0; i < n; i++) perm[i] = i;
    for (uint64_t i = n - 1; i > 0; i--) { uint64_t j = arc4random_uniform(i + 1); uint32_t t = perm[i]; perm[i] = perm[j]; perm[j] = t; }
    for (uint64_t i = 0; i < n; i++) *(uint64_t *)(mem + base + perm[i] * 16) = base + perm[(i + 1) % n] * 16;
    struct { const char *name; uint64_t pc, a, b, c, d; } t[] = {
        { "copy 32 KB (L1)  x200k ", 0x2000, 0x800000, 0x900000, 32768, 200000 },
        { "copy 8 MB (DRAM) x400  ", 0x2000, 0x1000000, 0x2000000, 8u << 20, 400 },
        { "pointer chase+store 1MB", 0x3000, base, 0, 0, 100000000 },
    };
    for (int i = 0; i < 3; i++) {
        uint64_t relpc = t[i].pc == 0x2000 ? 0x4000 : 0x5000;
        double off = 1e9, on = 1e9, sw = 1e9;
        for (int r = 0; r < 3; r++) {
            double a = run(t[i].pc, 0, t[i].a, t[i].b, t[i].c, t[i].d), b = run(t[i].pc, 1, t[i].a, t[i].b, t[i].c, t[i].d);
            double c = run(relpc, 0, t[i].a, t[i].b, t[i].c, t[i].d);
            if (a < off) off = a; if (b < on) on = b; if (c < sw) sw = c; }
        printf("%s  plain %.3fs | hardware TSO %.3fs (%+.1f%%) | software TSO (LDAPR/STLR) %.3fs (%+.1f%%)\n",
               t[i].name, off, on, 100 * (on / off - 1), sw, 100 * (sw / off - 1));
    }
    return 0;
}
