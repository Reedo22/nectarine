# Hardware TSO for translated x86 code without Rosetta (Hypervisor.framework)

Measured 2026-10-30 on an M1 Pro (8-CPU / 14-GPU), macOS 27.0.1. Build any probe with
`clang -O2 -arch arm64 X.c [X.S] -framework Hypervisor && codesign -f -s - --entitlements hv.entitlements X`.

| Probe | Result |
|---|---|
| `hvtso.c`: set vCPU `HV_SYS_REG_ACTLR_EL1` EnTSO (public API, macOS 15+, ad-hoc signed + hypervisor entitlement) | accepted: ACTLR 0 → 0x2 |
| `hvtso.c`: guest `hvc` round trip (exit to host + re-entry) | **0.92 µs** (a Wine syscall under Rosetta is ~0.9 µs) |
| `hvmax.c`: vCPUs per process | **64** (one VM per process; a vCPU is bound to its creating thread) |
| `litmus.c`: message passing, 2 vCPUs, MMU on, cacheable memory | TSO off: **85–91 M violations / 200 M reads**; TSO on: **0 / 400 M** |
| `tsocost.c`: hardware TSO cost vs plain ARM | 0% (L1 copy), +3% (DRAM copy), 0% (pointer chase) |
| `tsocost.c`: software TSO (every load LDAPR, every store STLR, as a naive translator emits) | **+108%** (L1 copy), **+134%** (DRAM copy), −9% (pointer chase) |

Rosetta itself does not use a VM: the kernel sets the TSO bit on the real core for translated threads. A
translator running its output inside a TSO vCPU pays a VM exit (~0.9 µs) on every switch to native code,
so the design has to keep those switches rare: fast paths inside the guest (timers, uncontended sync),
possibly native Wine unix code running inside the guest too, and exits only for kernel traps.
