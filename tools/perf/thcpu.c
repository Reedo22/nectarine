// thcpu <pid> <seconds> : CPU time per thread over an interval, with thread id (= sample's Thread_<id>) and name.
#include <libproc.h>
#include <sys/proc_info.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#ifndef PROC_PIDLISTTHREADIDS
#define PROC_PIDLISTTHREADIDS 28
#endif
typedef struct { uint64_t id; uint64_t t; char name[64]; } th_t;
static int snap(int pid, th_t *out, int max)
{
    uint64_t handles[2048]; int n = proc_pidinfo(pid, PROC_PIDLISTTHREADIDS, 0, handles, sizeof(handles)) / sizeof(uint64_t), k = 0;
    for (int i = 0; i < n && k < max; i++) {
        struct proc_threadinfo ti; struct proc_threadwithpathinfo tp;
        if (proc_pidinfo(pid, PROC_PIDTHREADID64INFO, handles[i], &ti, sizeof(ti)) != sizeof(ti)) continue;
        struct proc_threadinfo *p = &ti; uint64_t id = handles[i];
        if (proc_pidinfo(pid, PROC_PIDTHREADID64INFO, handles[i], &ti, sizeof(ti)) == sizeof(ti)) {}
        out[k].id = handles[i]; out[k].t = p->pth_user_time + p->pth_system_time;
        strncpy(out[k].name, p->pth_name, 63); out[k].name[63] = 0; k++; (void)tp; (void)id;
    }
    return k;
}
int main(int c, char **v)
{
    int pid = atoi(v[1]); double sec = c > 2 ? atof(v[2]) : 10;
    static th_t a[2048], b[2048]; int na = snap(pid, a, 2048); usleep((useconds_t)(sec * 1e6)); int nb = snap(pid, b, 2048);
    for (int i = 0; i < nb; i++) for (int j = 0; j < na; j++) if (a[j].id == b[i].id) {
        double d = (b[i].t - a[j].t) / 1e9 / sec;
        if (d > 0.02) printf("%5.1f%%  Thread_%llu  %s\n", d * 100, (unsigned long long)b[i].id, b[i].name[0] ? b[i].name : "-");
    }
    return 0;
}
