/****************************************************************************
 *
 * Copyright 2016 Samsung Electronics All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
 * either express or implied. See the License for the specific
 * language governing permissions and limitations under the License.
 *
 ****************************************************************************/
/****************************************************************************
 * arch/arm/src/armv7-r/arm_fullcontextrestore.S
 *
 *   Copyright (C) 2015 Gregory Nutt. All rights reserved.
 *   Author: Gregory Nutt <gnutt@nuttx.org>
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 * 3. Neither the name NuttX nor the names of its contributors may be
 *    used to endorse or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
 * OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
 * AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 * ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 ****************************************************************************/

/****************************************************************************
 * Included Files
 ****************************************************************************/

#include <tinyara/config.h>
#include <tinyara/irq.h>
#include "up_internal.h"
#include "svcall.h"

	.file	"arm_fullcontextrestore.S"

/****************************************************************************
 * Pre-processor Definitions
 ****************************************************************************/

/****************************************************************************
 * Public Symbols
 ****************************************************************************/
	.global up_mpucontextrestore
	.globl	up_fullcontextrestore

#ifdef CONFIG_ARCH_FPU
	.cpu	cortex-r4
#else
	.cpu	cortex-r4f
#endif
	.syntax	unified
	.file	"arm_fullcontextrestore.S"

/****************************************************************************
 * Public Functions
 ****************************************************************************/

	.text

/****************************************************************************
 * Name: up_fullcontextrestore
 *
 * Description:
 *   Restore the specified task context. Full prototype is:
 *
 *     void up_fullcontextrestore(uint32_t *restoreregs) noreturn_function;
 *
 * Return:
 *   None
 *
 ****************************************************************************/

	.globl	up_fullcontextrestore
	.type	up_fullcontextrestore, function

up_fullcontextrestore:

	/* On entry, a1 (r0) holds address of the register save area.  All other
	 * registers are available for use.
	 */
#ifdef CONFIG_ARCH_FPU
	/* First, restore the floating point registers.  Lets do this before we
	 * restore the ARM registers so that we have plenty of registers to
	 * work with.
	 */
	add		r1, r0, #(4*REG_S0)		/* r1=Address of FP register storage */

	/* Load all floating point registers.  Registers are loaded in numeric order,
	 * s0, s1, ... in increasing address order.
	 */

	vldmia	r1!, {s0-s31}			/* Restore the full FP context */

	/* Load the floating point control and status register.   At the end of the
	 * vstmia, r1 will point to the FPCSR storage location.
	 */

	ldr		r2, [r1], #4			/* Fetch the floating point control and status register */
	vmsr	fpscr, r2				/* Restore the FPCSR */
#endif

#if defined(CONFIG_BUILD_PROTECTED)
	/* For the protected build, we need to be able to transition gracefully
	 * between kernel- and user-mode tasks.  Here we do that with a system
	 * call; the system call will execute in kernel mode and but can return
	 * to either user or kernel mode.
	 */

	sub	sp, #4
	/* restore the MPU context information */
	str	lr,	[sp]
	bl up_mpucontextrestore
	ldr	lr,	[sp]
	add	sp, #4
	/* Perform the System call with R0=SYS_context_restore, R1=restoreregs */
	mov		r1, r0					/* R1: restoreregs */
	mov		r0, #SYS_context_restore	/* R0: SYS_context_restore syscall */
	svc		#0x900001				/* Perform the system call */

	/* This call should not return */

	bx		lr						/* Unnecessary ... will not return */

#else
	/* For a flat build, we can do all of this here... Just think of this as
	 * a longjmp() all on steriods.
	 */

	/* Recover all registers except for r0, r1, R15, and CPSR */

	add		r1, r0, #(4*REG_R2)		/* Offset to REG_R2 storage */
	ldmia	r1, {r2-r14}			/* Recover registers */

	/* Create a stack frame to hold the some registers */

	sub		sp, sp, #(3*4)			/* Frame for three registers */
	ldr		r1, [r0, #(4*REG_R0)]	/* Fetch the stored r0 value */
	str		r1, [sp]				/* Save it at the top of the stack */
	ldr		r1, [r0, #(4*REG_R1)]	/* Fetch the stored r1 value */
	str		r1, [sp, #4]			/* Save it in the stack */
	ldr		r1, [r0, #(4*REG_PC)]	/* Fetch the stored pc value */
	str		r1, [sp, #8]			/* Save it at the bottom of the frame */

	/* Now we can restore the CPSR.  We wait until we are completely
	 * finished with the context save data to do this. Restore the CPSR
	 * may re-enable and interrupts and we could be in a context
	 * where the save structure is only protected by interrupts being
	 * disabled.
	 */

	ldr		r1, [r0, #(4*REG_CPSR)]	/* Fetch the stored CPSR value */
	msr             spsr_cxsf, r1                   /* Set the SPSR */

	/* Now recover r0-r1, pc and cpsr, and destroying the stack frame */
	ldmia   sp!, {r0-r1, pc}^

#endif

	.size up_fullcontextrestore, . - up_fullcontextrestore
