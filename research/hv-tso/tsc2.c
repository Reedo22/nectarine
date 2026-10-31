#include <mach/mach_time.h>
#include <stdio.h>
#include <x86intrin.h>
int main(void)
{
    long long worst = 0;
    for (int i = 0; i < 1000000; i++) {
        uint64_t a = mach_continuous_time(), t = __rdtsc(), b = mach_continuous_time();
        long long d = (t < a) ? (long long)(a - t) : (t > b ? (long long)(t - b) : 0);   /* how far outside [a,b] */
        if (d > worst) worst = d;
    }
    uint64_t a = mach_continuous_time(), t = __rdtsc();
    printf("rdtsc - mach_continuous_time: %lld ns; worst excursion outside a bracketing pair: %lld ns\n",
           (long long)(t - a), worst);
    return 0;
}
