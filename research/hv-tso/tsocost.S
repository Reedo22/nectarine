.text
.globl _g_copy, _g_copy_end, _g_ptr, _g_ptr_end
.p2align 2
// x0=src x1=dst x2=bytes per pass (multiple of 16) x3=passes : copy loop, 8-byte loads/stores
_g_copy:
1:  mov x4, x0
    mov x5, x1
    mov x6, x2
2:  ldr x7, [x4], #8
    ldr x8, [x4], #8
    str x7, [x5], #8
    str x8, [x5], #8
    subs x6, x6, #16
    b.ne 2b
    subs x3, x3, #1
    b.ne 1b
    hvc #0
_g_copy_end:
.p2align 2
// x0=table x3=steps : dependent pointer chase with a store per step (latency-bound)
_g_ptr:
    mov x4, x0
1:  ldr x4, [x4]
    str x3, [x4, #8]
    subs x3, x3, #1
    b.ne 1b
    hvc #0
_g_ptr_end:
.globl _g_copy_rel, _g_copy_rel_end, _g_ptr_rel, _g_ptr_rel_end
.p2align 2
// same copy loop, software-TSO style (what FEX emits without hardware TSO): LDAPR loads, STLR stores
_g_copy_rel:
1:  mov x4, x0
    mov x5, x1
    mov x6, x2
2:  ldapr x7, [x4]
    add x4, x4, #8
    ldapr x8, [x4]
    add x4, x4, #8
    stlr x7, [x5]
    add x5, x5, #8
    stlr x8, [x5]
    add x5, x5, #8
    subs x6, x6, #16
    b.ne 2b
    subs x3, x3, #1
    b.ne 1b
    hvc #0
_g_copy_rel_end:
.p2align 2
_g_ptr_rel:
    mov x4, x0
1:  ldapr x4, [x4]
    add x9, x4, #8
    stlr x3, [x9]
    subs x3, x3, #1
    b.ne 1b
    hvc #0
_g_ptr_rel_end:
