# Copyright (C) 2026 Sunil Khare. All rights reserved. 
#
# nthr_sysv.s
#
# In the SysV scheme, variables in C functions can be optimised into registers,
# thus for garbage collection purposes we want to save not only the stack_ptr
# but also a series of six x86_64 registers to the thread context.
#
# Content of these registers is not used for the wasm32 target.
#  
################################################################################
#
# void nthr_arch_stack32(void)
#
    .att_syntax
	.text
	.globl	nthr_arch_stack32
	.type	nthr_arch_stack32,@function
nthr_arch_stack32:
	movq	nthr_current@gottpoff(%rip), %rax
	movq	%fs:(%rax), %rax
	movq	%rsp, 64(%rax)       # stack_ptr
	movq	%rbx, 104(%rax)      # regs[0]
	movq	%rbp, 112(%rax)      # regs[1]
	movq	%r12, 120(%rax)      # regs[2]
	movq	%r13, 128(%rax)      # regs[3]
	movq	%r14, 136(%rax)      # regs[4]
	movq	%r15, 144(%rax)      # regs[5]
	ret
	.size	nthr_arch_stack32, .-nthr_arch_stack32
	.section	.note.GNU-stack,"",@progbits
    