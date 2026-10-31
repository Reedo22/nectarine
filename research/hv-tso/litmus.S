// Guest code (EL1, MMU on). Copied into guest memory; position independent.
.text
.globl _guest_writer, _guest_writer_end, _guest_reader, _guest_reader_end
.p2align 2
// x0=&x x1=&y x2=iterations : for i in 1..n { x=i; y=i }
_guest_writer:
    mov x3, #0
1:  add x3, x3, #1
    str x3, [x0]
    str x3, [x1]
    subs x2, x2, #1
    b.ne 1b
    hvc #0
_guest_writer_end:
.p2align 2
// x0=&x x1=&y x2=iterations : r1=y; r2=x; if (r2 < r1) violations++ (x4)
_guest_reader:
    mov x4, #0
1:  ldr x5, [x1]
    ldr x6, [x0]
    cmp x6, x5
    cinc x4, x4, lo
    subs x2, x2, #1
    b.ne 1b
    hvc #0
_guest_reader_end:
