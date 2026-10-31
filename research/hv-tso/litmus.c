// litmus: message-passing test on two Hypervisor.framework vCPUs with the MMU on (normal cacheable memory),
// TSO off vs on. A reader that sees a newer y than x proves a reordering x86 forbids.
#include <Hypervisor/Hypervisor.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
extern char guest_writer[], guest_writer_end[], guest_reader[], guest_reader_end[];
#define MEM_SIZE (2u << 20)            /* 2 MB guest RAM at IPA 0 */
#define PT 0x1000                      /* L1 page table */
#define CODE_W 0x2000
#define CODE_R 0x3000
#define VAR_X 0x10000
#define VAR_Y 0x10200                  /* different 128-byte cache lines */
static uint8_t *mem; static int tso;
static uint64_t iters_w = 400000000ull, iters_r = 200000000ull;
static void setup(hv_vcpu_t v, uint64_t pc)
{
    hv_vcpu_set_sys_reg(v, HV_SYS_REG_MAIR_EL1, 0xff);                       /* attr0 = normal WB cacheable */
    /* T0SZ=32 (4 GB VA, starts at L1), IRGN0/ORGN0=WB, SH0=inner, TG0=4K, EPD1, IPS=36 bit */
    hv_vcpu_set_sys_reg(v, HV_SYS_REG_TCR_EL1, 32 | (1u << 8) | (1u << 10) | (3u << 12) | (1u << 23) | (1ull << 32));
    hv_vcpu_set_sys_reg(v, HV_SYS_REG_TTBR0_EL1, PT);
    hv_vcpu_set_sys_reg(v, HV_SYS_REG_SCTLR_EL1, 0x30d00800 | 1 | (1 << 2) | (1 << 12));  /* RES1 | M | C | I */
    uint64_t a = 0; hv_vcpu_get_sys_reg(v, HV_SYS_REG_ACTLR_EL1, &a);
    hv_vcpu_set_sys_reg(v, HV_SYS_REG_ACTLR_EL1, tso ? (a | 2) : (a & ~2ull));
    hv_vcpu_set_reg(v, HV_REG_CPSR, 0x3c5);
    hv_vcpu_set_reg(v, HV_REG_PC, pc);
    hv_vcpu_set_reg(v, HV_REG_X0, VAR_X); hv_vcpu_set_reg(v, HV_REG_X1, VAR_Y);
}
static void *run(void *arg)
{
    int reader = (int)(long)arg; hv_vcpu_t v; hv_vcpu_exit_t *e;
    hv_vcpu_create(&v, &e, NULL);
    setup(v, reader ? CODE_R : CODE_W);
    hv_vcpu_set_reg(v, HV_REG_X2, reader ? iters_r : iters_w);
    hv_vcpu_run(v);
    uint64_t ec = (e->exception.syndrome >> 26) & 0x3f, viol = 0, actlr = 0;
    hv_vcpu_get_reg(v, HV_REG_X4, &viol); hv_vcpu_get_sys_reg(v, HV_SYS_REG_ACTLR_EL1, &actlr);
    if (ec != 0x16) printf("  %s: unexpected exit reason %u ec %#llx far %#llx\n", reader ? "reader" : "writer",
                           e->reason, ec, e->exception.virtual_address);
    if (reader) printf("  TSO %s (ACTLR %#llx): %llu ordering violations in %llu reads\n", tso ? "ON " : "off", actlr, viol, iters_r);
    hv_vcpu_destroy(v); return NULL;
}
int main(void)
{
    hv_vm_create(NULL);
    mem = mmap(NULL, MEM_SIZE, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    hv_vm_map(mem, 0, MEM_SIZE, HV_MEMORY_READ | HV_MEMORY_WRITE | HV_MEMORY_EXEC);
    uint64_t *l1 = (uint64_t *)(mem + PT);
    l1[0] = 0x0 | (1 << 10) /*AF*/ | (3 << 8) /*inner shareable*/ | (0 << 2) /*attr0*/ | 1 /*block*/;
    memcpy(mem + CODE_W, guest_writer, guest_writer_end - guest_writer);
    memcpy(mem + CODE_R, guest_reader, guest_reader_end - guest_reader);
    for (tso = 0; tso <= 1; tso++) {
        for (int rep = 0; rep < 2; rep++) {
            memset(mem + VAR_X, 0, 0x400);
            pthread_t w, r;
            pthread_create(&w, NULL, run, (void *)0); pthread_create(&r, NULL, run, (void *)1);
            pthread_join(r, NULL); pthread_join(w, NULL);
        }
    }
    return 0;
}
