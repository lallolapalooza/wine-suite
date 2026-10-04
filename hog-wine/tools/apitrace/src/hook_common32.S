/*
 * hook_common32.S -- i386 (Win32) import tracer for apihook.dll.
 *
 * Every patched IAT slot points at a 15-byte runtime-generated stub:
 *
 *     68 <idx32>              push  imm32 idx          ; hook index
 *     68 <orig32>             push  imm32 orig         ; real target
 *     E9 <rel32>              jmp   hook_common32
 *
 * On entry to hook_common32 the stack is exactly the caller's frame with two
 * extra dwords on top:
 *
 *     [esp+ 0] = orig
 *     [esp+ 4] = idx
 *     [esp+ 8] = caller's return address  (S)
 *     [esp+12] = arg0, [esp+16] = arg1, ...   (Win32 stdcall arguments)
 *
 * The tracer logs the arguments (S + 4 + 4*i) and then *tail-jumps* to the real
 * function with the caller's original frame restored, so the callee returns
 * straight to the caller.  Nothing about the stack is rebuilt, which makes the
 * hook independent of argument count, calling convention and ABI stack
 * alignment.  The trade-off is that the return value is not observed (the
 * Windows-side 32-bit log is a call/argument inventory; return values for the
 * failure analysis come from the Wine relay log).
 */
	.text
	.globl	_hook_common32
	.def	_hook_common32; .scl 2; .type 32; .endef
_hook_common32:
	pushal				/* save all GP regs; ebp/ebx/esi/edi must
					   survive, eax/ecx/edx are free */
	leal	40(%esp), %edx		/* S = &caller return address */
	movl	36(%esp), %eax		/* idx                        */
	pushl	%edx			/* arg2: S   */
	pushl	%eax			/* arg1: idx */
	call	_trace_pre32		/* cdecl                      */
	addl	$8, %esp
	popal				/* restore every register     */
	popl	%eax			/* eax = orig                 */
	popl	%ecx			/* drop idx                   */
	jmp	*%eax			/* -> real target; its own ret returns
					   directly to the caller           */
