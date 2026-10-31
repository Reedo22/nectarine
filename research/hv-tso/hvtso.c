// hvtso: can an ad-hoc signed process put a Hypervisor.framework vCPU in TSO mode, and what does a
// guest->host exit (HVC round trip) cost?
#include <Hypervisor/Hypervisor.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#define CHECK(x) do { hv_return_t r_ = (x); if (r_ != HV_SUCCESS) { printf("%s failed: %#x\n", #x, r_); return 1; } } while (0)
int main(void)
{
    CHECK(hv_vm_create(NULL));
    // guest code at IPA 0x10000: loop { hvc #0 }
    uint32_t *code = mmap(NULL, 0x4000, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    code[0] = 0xd4000002;   /* hvc #0 */
    code[1] = 0x17ffffff;   /* b -1 */
    CHECK(hv_vm_map(code, 0x10000, 0x4000, HV_MEMORY_READ | HV_MEMORY_EXEC));
    hv_vcpu_t vcpu; hv_vcpu_exit_t *exit;
    CHECK(hv_vcpu_create(&vcpu, &exit, NULL));
    CHECK(hv_vcpu_set_reg(vcpu, HV_REG_PC, 0x10000));
    CHECK(hv_vcpu_set_reg(vcpu, HV_REG_CPSR, 0x3c5));            /* EL1h, interrupts masked, MMU off */
    uint64_t actlr = 0;
    CHECK(hv_vcpu_get_sys_reg(vcpu, HV_SYS_REG_ACTLR_EL1, &actlr));
    printf("ACTLR_EL1 before: %#llx\n", actlr);
    CHECK(hv_vcpu_set_sys_reg(vcpu, HV_SYS_REG_ACTLR_EL1, actlr | 2));
    CHECK(hv_vcpu_get_sys_reg(vcpu, HV_SYS_REG_ACTLR_EL1, &actlr));
    printf("ACTLR_EL1 after setting EnTSO: %#llx (TSO %s)\n", actlr, (actlr & 2) ? "ON" : "off");

    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    const int N = 200000; int ok = 0;
    uint64_t t0 = mach_absolute_time();
    for (int i = 0; i < N; i++) {
        CHECK(hv_vcpu_run(vcpu));
        if (exit->reason == HV_EXIT_REASON_EXCEPTION && ((exit->exception.syndrome >> 26) & 0x3f) == 0x16) ok++;
    }
    double ns = (double)(mach_absolute_time() - t0) * tb.numer / tb.denom / N;
    printf("HVC round trips: %d/%d, %.0f ns each (%.2f us)\n", ok, N, ns, ns / 1000);
    return 0;
}
