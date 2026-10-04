/*
 * hook_common.S -- x86-64 (Win64) call-through trampoline for apihook.dll.
 *
 * Every patched IAT slot points at a 29-byte runtime-generated stub:
 *
 *     68 <idx32>              push  imm32 idx          ; hook index
 *     49 BB <orig64>          mov   r11, orig          ; real target
 *     FF 25 00 00 00 00       jmp   qword ptr [rip+0]  ; -> hook_common
 *     <hook_common addr>
 *
 * hook_common() must
 *   - preserve every register the hooked caller expects (args in rcx/rdx/r8/r9,
 *     xmm0-3, and rax which carries the vector-arg count for varargs - AL),
 *   - give the real target a stack frame that is identical in *content* to the
 *     one the original caller had set up, so stack arguments (arg5..) are read
 *     from the right slots,
 *   - regain control after the target returns so the return value can be logged.
 *
 * On entry: rsp = S-8, [rsp] = idx, r11 = target, S = caller's rsp as seen by
 * the hooked function (Win64: S % 16 == 8, [S] = caller's return address,
 * [S+8..S+0x28) = shadow space, [S+0x28+8k] = stack argument k).
 *
 * The callee frame is built *below* our own frame (a fresh 0xA8-byte area X),
 * so the target's own stack usage can never clobber our saved registers.
 */
	.text
	.globl	hook_common
	.def	hook_common; .scl 2; .type 32; .endef
hook_common:
	pushq	%rbp
	movq	%rsp, %rbp		/* rbp = S-0x10: 0(%rbp)=caller rbp, 8(%rbp)=idx, 0x10(%rbp)=S */
	subq	$0x108, %rsp		/* own frame; rsp % 16 == 0 from here on */

	movq	%rax, -0x08(%rbp)	/* incoming rax (varargs AL) */
	movq	%rcx, -0x10(%rbp)	/* a0 */
	movq	%rdx, -0x18(%rbp)	/* a1 */
	movq	%r8,  -0x20(%rbp)	/* a2 */
	movq	%r9,  -0x28(%rbp)	/* a3 */
	movq	%r11, -0x30(%rbp)	/* original target */
	movq	8(%rbp), %r10
	movq	%r10, -0x38(%rbp)	/* hook index */
	movups	%xmm0, -0x50(%rbp)
	movups	%xmm1, -0x60(%rbp)
	movups	%xmm2, -0x70(%rbp)
	movups	%xmm3, -0x80(%rbp)

	/* fresh callee frame X = rsp-0xA8 (X % 16 == 8), holds a copy of the
	   shadow space + 16 stack-argument slots of the original caller. */
	subq	$0xA8, %rsp
	leaq	.Lpost(%rip), %rax
	movq	%rax, 0x00(%rsp)	/* return address seen by the target */
	movups	0x38(%rbp), %xmm0	/* S+0x28: stack arg 4 */
	movups	%xmm0, 0x28(%rsp)
	movups	0x48(%rbp), %xmm1	/* S+0x38: stack arg 6 */
	movups	%xmm1, 0x38(%rsp)
	movups	0x58(%rbp), %xmm2	/* S+0x48: stack arg 8 */
	movups	%xmm2, 0x48(%rsp)
	movups	0x68(%rbp), %xmm3	/* S+0x58 */
	movups	%xmm3, 0x58(%rsp)
	movups	0x78(%rbp), %xmm4	/* S+0x68 */
	movups	%xmm4, 0x68(%rsp)
	movups	0x88(%rbp), %xmm5	/* S+0x78 */
	movups	%xmm5, 0x78(%rsp)
	movups	0x98(%rbp), %xmm6	/* S+0x88 */
	movups	%xmm6, 0x88(%rsp)
	movups	0xA8(%rbp), %xmm7	/* S+0x98 */
	movups	%xmm7, 0x98(%rsp)

	/* restore caller state and enter the real function */
	movq	-0x08(%rbp), %rax
	movq	-0x10(%rbp), %rcx
	movq	-0x18(%rbp), %rdx
	movq	-0x20(%rbp), %r8
	movq	-0x28(%rbp), %r9
	movups	-0x50(%rbp), %xmm0
	movups	-0x60(%rbp), %xmm1
	movups	-0x70(%rbp), %xmm2
	movups	-0x80(%rbp), %xmm3
	movq	-0x30(%rbp), %r11
	jmp	*%r11

.Lpost:					/* target returned, rsp == X+8, rax = retval */
	movq	%rax, -0x40(%rbp)
	leaq	-0x108(%rbp), %rsp	/* back to own frame */
	/* trace_emit(idx, a0, a1, a2, a3, ret, caller_rsp) */
	movq	-0x38(%rbp), %rcx
	movq	-0x10(%rbp), %rdx
	movq	-0x18(%rbp), %r8
	movq	-0x20(%rbp), %r9
	movq	-0x28(%rbp), %rax
	movq	%rax, 0x20(%rsp)
	movq	-0x40(%rbp), %rax
	movq	%rax, 0x28(%rsp)
	leaq	0x10(%rbp), %rax	/* S */
	movq	%rax, 0x30(%rsp)
	call	trace_emit

	movq	-0x40(%rbp), %rax	/* hand the target's return value back */
	movq	0x00(%rbp), %r11	/* caller's rbp */
	leaq	0x10(%rbp), %rsp	/* rsp = S, [S] untouched == caller's return address */
	movq	%r11, %rbp
	ret
