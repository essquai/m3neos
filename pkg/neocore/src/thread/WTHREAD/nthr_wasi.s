# Copyright (C) 2026 Sunil Khare. All rights reserved. 
#
# nthr_wasi.s
#
# In the wasi scheme, __stack_pointer is a wasm global rather than a variable
# accessible from "C". To replace the current stack pointer when spawning a
# thread, wasi_thread_start must therefore be formulated in clang wasm assembly.
# Once the stack is set, the thread continues via "nthr_start32".
#
# Fetching the stack pointer is likewise performed by clang wasm
# assembly, via "nthr_wasi_sp".
#  
################################################################################
#
# void wasi_thread_start(int tid, int arg)
#
	.globaltype __stack_pointer, i32
	.functype nthr_start32 (i32, i32) -> ()
	.hidden nthr_start32
	.globl wasi_thread_start
	.export_name wasi_thread_start, wasi_thread_start
	.section .text.wasi_thread_start,"",@
wasi_thread_start:
	.functype wasi_thread_start (i32, i32) -> ()
	local.get 1
	i32.load 40          # offsetof(nthr_context_t, stack_top); asserted
	global.set __stack_pointer
	local.get 0
	local.get 1
	call nthr_start32
    local.get 1
    i32.const 1
    i32.atomic.store 80          # offsetof(nthr_context_t, ended); asserted
    local.get 1
    i32.const 1
    memory.atomic.notify 80      # awaken nthr_arch_reap32
    drop
	end_function

################################################################################
#
# void *nthr_wasi_sp(void)
#
	.globl nthr_wasi_sp
	.section .text.nthr_wasi_sp,"",@
nthr_wasi_sp:
	.functype nthr_wasi_sp () -> (i32)
	global.get __stack_pointer
	end_function