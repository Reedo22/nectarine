// hvmax: how many vCPUs can one process have (each vCPU is bound to its own host thread)?
#include <Hypervisor/Hypervisor.h>
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>
static int made = 0; static pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
static void *worker(void *a)
{
    hv_vcpu_t v; hv_vcpu_exit_t *e;
    if (hv_vcpu_create(&v, &e, NULL) == HV_SUCCESS) { pthread_mutex_lock(&m); made++; pthread_mutex_unlock(&m); }
    sleep(3); return NULL;
}
int main(void)
{
    uint32_t max = 0;
    if (hv_vm_create(NULL) != HV_SUCCESS) { puts("vm create failed"); return 1; }
    if (hv_vm_get_max_vcpu_count(&max) == HV_SUCCESS) printf("reported max vCPUs per VM: %u\n", max);
    pthread_t t[256];
    for (int i = 0; i < 256; i++) pthread_create(&t[i], NULL, worker, NULL);
    sleep(1); printf("vCPUs actually created concurrently: %d of 256 threads\n", made);
    for (int i = 0; i < 256; i++) pthread_join(t[i], NULL);
    return 0;
}
