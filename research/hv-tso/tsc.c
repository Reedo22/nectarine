// tsc: what does rdtsc return under Rosetta (rate vs mach_absolute_time, cost, cross-thread monotonicity)?
#include <mach/mach_time.h>
#include <pthread.h>
#include <stdio.h>
#include <stdint.h>
#include <time.h>
#include <unistd.h>
#include <x86intrin.h>
static volatile uint64_t shared_tsc; static volatile int stop; static uint64_t backwards;
static void *pinger(void *a) { while (!stop) { uint64_t t = __rdtsc(); if (t < shared_tsc) backwards++; shared_tsc = t; } return NULL; }
int main(void)
{
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    uint64_t t0 = __rdtsc(), m0 = mach_absolute_time(); struct timespec s0, s1; clock_gettime(CLOCK_MONOTONIC_RAW, &s0);
    usleep(500000);
    uint64_t t1 = __rdtsc(), m1 = mach_absolute_time(); clock_gettime(CLOCK_MONOTONIC_RAW, &s1);
    double sec = (s1.tv_sec - s0.tv_sec) + (s1.tv_nsec - s0.tv_nsec) / 1e9;
    printf("rdtsc rate: %.3f MHz; mach_absolute_time rate: %.3f MHz (timebase %u/%u); rdtsc/mach ratio %.6f\n",
           (t1 - t0) / sec / 1e6, (m1 - m0) / sec / 1e6, tb.numer, tb.denom, (double)(t1 - t0) / (m1 - m0));
    printf("rdtsc - mach_absolute_time offset now: %lld\n", (long long)(__rdtsc() - mach_absolute_time()));
    const int N = 20000000; uint64_t x = 0, a = mach_absolute_time();
    for (int i = 0; i < N; i++) x += __rdtsc();
    uint64_t b = mach_absolute_time();
    printf("rdtsc cost: %.1f ns (sink %llu)\n", (double)(b - a) * tb.numer / tb.denom / N, (unsigned long long)(x & 1));
    pthread_t th[4]; for (int i = 0; i < 4; i++) pthread_create(&th[i], NULL, pinger, NULL);
    sleep(2); stop = 1; for (int i = 0; i < 4; i++) pthread_join(th[i], NULL);
    printf("cross-thread backwards observations: %llu (racy check; small numbers are store races, not clock skew)\n", (unsigned long long)backwards);
    return 0;
}
