/*
 *  armboot - Startup Code for S3C6410/ARM1176 CPU-core
 *
 * Copyright (c) 2007	Samsung Electronics
 *
 * Copyright (C) 2008
 * Guennadi Liakhovetki, DENX Software Engineering, <lg@denx.de>
 *
 * See file CREDITS for list of people who contributed to this
 * project.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	 See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston,
 * MA 02111-1307 USA
 *
 * 2007-09-21 - Restructured codes by jsgood (jsgood.yang@samsung.com)
 * 2007-09-21 - Added MoviNAND and OneNAND boot codes by
 * jsgood (jsgood.yang@samsung.com)
 * Base codes by scsuh (sc.suh)
 */

#include <config.h>
#include <version.h>
#ifdef CONFIG_ENABLE_MMU
#include <asm/proc/domain.h>
#endif
#include <asm/arch/s3c6410.h>

#if !defined(CONFIG_ENABLE_MMU) && !defined(CONFIG_SYS_PHY_UBOOT_BASE)
#define CONFIG_SYS_PHY_UBOOT_BASE	CONFIG_SYS_UBOOT_BASE
#endif

/*
 *************************************************************************
 *
 * Jump vector table as in table 3.1 in [1]
 *
 *************************************************************************
 */

.globl _start
_start: b	reset
#ifndef CONFIG_NAND_SPL
	ldr	pc, _undefined_instruction
	ldr	pc, _software_interrupt
	ldr	pc, _prefetch_abort
	ldr	pc, _data_abort
	ldr	pc, _not_used
	ldr	pc, _irq
	ldr	pc, _fiq

_undefined_instruction:
	.word undefined_instruction
_software_interrupt:
	.word software_interrupt
_prefetch_abort:
	.word prefetch_abort
_data_abort:
	.word data_abort
_not_used:
	.word not_used
_irq:
	.word irq
_fiq:
	.word fiq
_pad:
	.word 0x12345678 /* now 16*4=64 */
#else
	. = _start + 64
#endif

.global _end_vect
_end_vect:
	.balignl 16,0xdeadbeef
/* .balignl����˼�ǣ��Ե�ǰ��ַΪ��ʼ��ʼ���ҵ���һ�γ��ֵ��Ե�һ������(16)Ϊ�������ĵ�ַ����������Ϊ������ַ��
 *�����������ַǰ��洢4���ֽڳ��ȵ����ݣ��洢�������ǵڶ��������������ǰ��ַ�����ǵ�һ�������ı�������û����
 *�ݱ�д�뵽�ڴ档���þ���Ϊ�ڴ�����ǣ���������ͱ�ʾ�����λ�������һ�����������õ��ڴ棬�����λ����ǰ����ֹ���ʡ�
 */
/*
 *************************************************************************
 *
 * Startup Code (reset vector)
 *
 * 1.do important init only if we don't start from memory!
 * 2.setup Memory and board specific bits prior to relocation.
 * 3.relocate armboot to ram
 * 4.setup stack
 *
 *************************************************************************
 */

_TEXT_BASE:
	.word	TEXT_BASE	//��board/samsung/smdk6410/config.mk�ļ���

/*
 * Below variable is very important because we use MMU in U-Boot.
 * Without it, we cannot run code correctly before MMU is ON.
 * by scsuh.
 */
_TEXT_PHY_BASE:
	.word	CONFIG_SYS_PHY_UBOOT_BASE	//#define CONFIG_SYS_PHY_UBOOT_BASE	(CONFIG_SYS_SDRAM_BASE + 0x07e00000)
						//#define CONFIG_SYS_SDRAM_BASE	0x50000000. ��ӽ������0x57e00000

.globl _armboot_start
_armboot_start:
	.word _start		//_armboot_start�е�ֵ����_start��ַ(0x0)

/*
 * These are defined in the board-specific linker script.
 */
.globl _bss_start
_bss_start:
	.word __bss_start

.globl _bss_end
_bss_end:
	.word _end

/*
 * the actual reset codeʵ�ʵĸ�λ����
 */

reset:
	/*
	 * set the cpu to SVC32 mode(ARM�ķ���Ȩģʽ���û�ģʽ������ģʽ������Ȩģʽ)
	 *CPSR STATE:
	 *bit[31:8]	 bit7		  bit6		   bit5    	  bit[4:0]
	 * no care    IRQ disable          FIQ disable         Thumb state bit      Mode bits
	 *set cpsr bit[7:0] to 11010011:����IRQ/FIQ������ARM32ָ�״̬��SVCģʽ��
	 */
	mrs	r0, cpsr
	bic	r0, r0, #0x3f
	orr	r0, r0, #0xd3
	msr	cpsr, r0

/*
 *************************************************************************
 *
 * CPU_init_critical registers
 * CPU��ʼ���ؼ��Ĵ���
 * 1.setup important registers
 * 2.setup memory timing
 *
 *************************************************************************
 */
	/*
	 * we do sys-critical inits only at reboot,
	 * not when booting from ram!
	 */
cpu_init_crit:
	/*
	 * When booting from NAND - it has definitely been a reset, so, no need
	 * to flush caches and disable the MMU
	 *����NAND����ʱ��������ֻ�Ǹ�λ���Ͳ��ð����caches�ͽ���MMU�ˡ�
	 */
#ifndef CONFIG_NAND_SPL		//û���ҵ�define!
				//nand_spl/board/samsung/smdk6410/Makefile����CONFIG_NAND_SPL = y
	/*
	 * flush v4 I/D caches
	 */
	mov	r0, #0
	mcr	p15, 0, r0, c7, c7, 0	/* flush v3/v4 cache.�������ݡ�ָ��cache,���branch target cache��Branch Target Address Cache(BTAC) */
	mcr	p15, 0, r0, c8, c7, 0	/* flush v4 TLB */

	/*
	 * disable MMU stuff and caches
	 */
	mrc	p15, 0, r0, c1, c0, 0	/* ��c1�����ݵ�r0�Ĵ���.Read Control Register configuration data */
	bic	r0, r0, #0x00002300	@ clear bits 13, 9:8 (--V- --RS)
	bic	r0, r0, #0x00000087	@ clear bits 7, 2:0 (B--- -CAM)
	orr	r0, r0, #0x00000002	/* set bit 1 (A) Align	 ���������ʹ�� Strict alignment fault checking enabled.*/
	orr	r0, r0, #0x00001000	/* set bit 12 (I) I-Cache  ָ��catchʹ�ܡ�Instruction Cache enabled */
	/* Prepare to disable the MMU */
	adr	r1, mmu_disable_phys	/* ȡ�ñ�Ż���PC�ĵ�ֵַ���浽r1�У���Ϊ���ֶ��룬�����ڻ���PCֵ��-1020~1020(-2^10~2^10)��Χ��Ѱַ */
	/* We presume we're within the first 1024 bytes */
	and	r1, r1, #0x3fc		//r1&0b11 1111 1100,ֻȡĩβ10λ(�ֶ��룬��ĩ2λΪ0)���ƫ�Ƶ�ַ
	ldr	r2, _TEXT_PHY_BASE	//ȡ�ñ�ŵĴ��洢�����ݣ��浽r2�С����������0x57e00000������r2=0x57e00000
	ldr	r3, =0xfff00000		//������
	and	r2, r2, r3		//r2��20λ��0(1M)����������0!��λ�ֲ��䣬���е���Ҫ����....
	orr	r2, r2, r1		//r2=0x57e00000|(r1&0x3fc)=0x57e003fc��������Ϊ������������PC��ת��׼����
					//�����ַ��mmu_disable_phys����0x57e003fc��mDDR�е�(��û��ʹ��MMUʱ)��������
	b	mmu_disable

	.align 5	//ARM��.align 5����2��5�η����룬Ҳ����4�ֽڶ���.
	/* Run in a single cache-line */
mmu_disable:
	mcr	p15, 0, r0, c1, c0, 0	//��r0д��c1��ȥ������mmu
	nop
	nop
	mov	pc, r2					//��r2=0x57e00000+(r1&0x3fc)=0x57e003fc��ִַ�г�������������???
							//�����ַ��mmu_disable_phys����0x57e003fc��mDDR�У����ڻ�û�г�ʼ��mDDR�ذ�������
#endif

mmu_disable_phys:			//��ʼ��Ӳ��(����)
	/* Peri port setup */
	ldr	r0, =0x70000000
	orr	r0, r0, #0x13
	mcr	p15,0,r0,c15,c2,4       @ 256M (0x70000000 - 0x7fffffff)

	/*
	 * Go setup Memory and board specific bits prior to relocation.
	 */
	//�ؿ��Ź�����GPIO��0���жϡ������������жϡ������ж�ΪIRQģʽ(����FIQģʽ)�����жϷ��񡢳�ʼ����ʱ�ӡ���ʼ�����Դ���(UART0)��
	//Nandflash���ڴ�(mDDR)��Wakeup support��
	bl	lowlevel_init		/* go setup pll,mux,memory */

after_copy:
//#ifdef CONFIG_ENABLE_MMU	//��ִ��!uboot\board\samsung\smdk6410\config.mk,TEXT_BASE = $(RAM_TEXT),$(RAM_TEXT)=0x57e00000.
//enable_mmu:
//	/* enable domain access */
//	ldr	r5, =0x0000ffff
//	mcr	p15, 0, r5, c3, c0, 0	/* load domain access register, D0~D7 set to Manager*/
	/* The purpose of the fields D15-D0 in the register is to define the access permissions for each one of the 16 domains.
	 *b00 = No access, reset value. Any access generate s a domain fault.b11 = Manager. Accesses are not checked against the
	 *access permission bits in the TLB entry, so a permission fault ca nnot be generated.
	 */

	/* Set the TTB register */
//	ldr	r0, _mmu_table_base
//	ldr	r1, =CONFIG_SYS_PHY_UBOOT_BASE
//	ldr	r2, =0xfff00000
//	bic	r0, r0, r2	//mmu_table��12λ��0
//	orr	r1, r0, r1	//��12λ��Ϊ0x57ex_xxxx
//	mcr	p15, 0, r1, c2, c0, 0	//Holds the translation table base address, the physical address of the first
					//level translation table. The reset value is 0.

	/* Enable the MMU */
//	mrc	p15, 0, r0, c1, c0, 0	//Read Control Register configuration data to r0.
//	orr	r0, r0, #1		/* Set CR_M to enable MMU */

	/* Prepare to enable the MMU */
//	adr	r1, skip_hw_init
//	and	r1, r1, #0x3fc
//	ldr	r2, _TEXT_BASE		//��board/samsung/smdk6410/config.mk�ļ���,Ĭ��Ӧ��û�п�MMU����
//	ldr	r3, =0xfff00000
//	and	r2, r2, r3
//	orr	r2, r2, r1		//0x57e003fc��0xc7e003fc
//	b	mmu_enable

//	.align 5	//2^5 bit align, means 4 Byte align
	/* Run in a single cache-line */
//mmu_enable:
//
//	mcr	p15, 0, r0, c1, c0, 0	//r0�ĵ�0λ==1������Ϊԭc1�е�ֵ
//	nop
//	nop
//	mov	pc, r2			////0x57e003fc��0xc7e003fc,���ʹ����MMU����Ӧ��Ϊ����
//#endif

skip_hw_init:
	/* Set up the stack */
stack_setup:
	/* ���MMUʹ���ˣ�CONFIG_SYS_UBOOT_BASE����0xc7e0_0000,�������0x57e0_0000 */
	ldr	r0, =CONFIG_SYS_UBOOT_BASE	/* base of copy in DRAM */
	sub	r0, r0, #CONFIG_SYS_MALLOC_LEN	/* malloc area: 1024*1024Bytes(1MB),(CONFIG_ENV_SIZE(0x4000)+1024*1024)=0x104000 */
						//r0=0x57e00000-0x104000=0x57cfc000
	sub	r0, r0, #CONFIG_SYS_GBL_DATA_SIZE /* bdinfo :128Bytes for initial data */
						//r0=0x57cfc000-128=0x57CFBF80
	sub	sp, r0, #12		/* leave 3 words for abort-stack    */

clear_bss:
	ldr	r0, _bss_start		/* find start of bss segment        */
	ldr	r1, _bss_end		/* stop here                        */
	mov 	r2, #0			/* clear                            */

clbss_l:
	str	r2, [r0]		/* clear loop...                    */
	add	r0, r0, #4		// 4 Bytes per cycle
	cmp	r0, r1
	ble	clbss_l

#ifndef CONFIG_NAND_SPL		//û���ҵ�define!ִ��!
	ldr	pc, _start_armboot

_start_armboot:
	.word start_armboot
#else
	b	nand_boot
/*	.word nand_boot*/
#endif

#ifdef CONFIG_ENABLE_MMU
_mmu_table_base:
	.word mmu_table
#endif

#ifndef CONFIG_NAND_SPL
/*
 * we assume that cache operation is done before. (eg. cleanup_before_linux())
 * actually, we don't need to do anything about cache if not use d-cache in
 * U-Boot. So, in this function we clean only MMU. by scsuh
 *
 * void	theLastJump(void *kernel, int arch_num, uint boot_params);
 */
#ifdef CONFIG_ENABLE_MMU
	.globl theLastJump
theLastJump:
	mov	r9, r0
	ldr	r3, =0xfff00000
	ldr	r4, _TEXT_PHY_BASE	//ȡ�ñ�ŵĴ��洢�����ݣ��浽r2�С����������0x57e00000������r2=0x57e00000
	adr	r5, phy_last_jump
	bic	r5, r5, r3
	orr	r5, r5, r4
	mov	pc, r5		//��12λ��Ϊ0x57e
phy_last_jump:
	/*
	 * disable MMU stuff
	 */
	mrc	p15, 0, r0, c1, c0, 0
	bic	r0, r0, #0x00002300	/* clear bits 13, 9:8 (--V- --RS) */
	bic	r0, r0, #0x00000087	/* clear bits 7, 2:0 (B--- -CAM) */
	orr	r0, r0, #0x00000002	/* set bit 2 (A) Align */
	orr	r0, r0, #0x00001000	/* set bit 12 (I) I-Cache */
	mcr	p15, 0, r0, c1, c0, 0

	mcr	p15, 0, r0, c8, c7, 0	/* flush v4 TLB */

	mov	r0, #0
	mov	pc, r9
#endif
/*
 *************************************************************************
 *
 * Interrupt handling
 *
 *************************************************************************
 */
@
@ IRQ stack frame.
@
#define S_FRAME_SIZE	72

#define S_OLD_R0	68
#define S_PSR		64
#define S_PC		60
#define S_LR		56
#define S_SP		52
#define S_IP		48
#define S_FP		44
#define S_R10		40
#define S_R9		36
#define S_R8		32
#define S_R7		28
#define S_R6		24
#define S_R5		20
#define S_R4		16
#define S_R3		12
#define S_R2		8
#define S_R1		4
#define S_R0		0

#define MODE_SVC 0x13		//CPSR[4:0]=10011 for SVC Mode
#define I_BIT	 0x80		//CPSR[7]=1, IRQ Disabled

/*
 * use bad_save_user_regs for abort/prefetch/undef/swi ...
 */

	.macro	bad_save_user_regs
	/* carve out/����/ a frame on current user stack */
	sub	sp, sp, #S_FRAME_SIZE	//S_FRAME_SIZE=72
	/* Save user registers (now in svc mode) r0-r12 */
	stmia	sp, {r0 - r12}	//ia: increase after, sp=sp+4*13-4.���sp���!����sp=sp+4*13
				// Ҫע����ǣ����ָ��ִ�����sp��ֵ�ָֻ���ԭֵ�����ǡ�sub sp, sp, #S_FRAME_SIZE�����ֵ(���ԣ���Ϊsp��û��!�š�)

	ldr	r2, _armboot_start	//r2=_start��ַ�洢������,Ҫ����һ��,Ӧ����0x57e00000
	sub	r2, r2, #(CONFIG_SYS_MALLOC_LEN)//CFG_MALLOC_LEN�ǶѵĴ�С,CONFIG_STACKSIZE��������������ʱ��ջ��С
	/* set base 2 words into abort stack */
	sub	r2, r2, #(CONFIG_SYS_GBL_DATA_SIZE+8)// CFG_GBL_DATA_SIZE��һ��ȫ�ֱ����Ĵ�С��8�������֣�������ŷ�����Щ�쳣ʱ��pc��cpsr�Ĵ���
	/* get values for "aborted" pc and cpsr (into parm regs) */
	ldmia	r2, {r2 - r3}	// �ѷ����쳣ʱ��ʹ��get_bad_stack�����pc��cpsr�Ĵ������ص�r2,r3

	/* grab pointer to old stack */
	add	r0, sp, #S_FRAME_SIZE	 // r0=ԭ����SPֵ

	add	r5, sp, #S_SP	// �����ָ���ԭ��SP֮�ϣ�Ҳ����������Ĵ�����,S_SP=52����ʾ��ԭ��SP + 52���ĵط����Ǳ���sp�Ĵ���
	mov	r1, lr
	/* save sp_SVC, lr_SVC, pc, cpsr */
	stmia	r5, {r0 - r3}	//��ԭ��SP + 52���ĵط� ���� r0������ԭ����SPֵ��������sp_SVC�������ж�ʱ��SPֵ
				// ��ԭ��SP + 56���ĵط� ���� r1����lr������lr_SVC�������ж�ʱ��lrֵ
				// ��ԭ��SP + 60���ĵط� ���� r2����pc�����ǡ�ʹ��get_bad_stack�����pc���������ж�ʱ��pcֵ
				// ��ԭ��SP + 64���ĵط� ���� r3����cpsr�����ǡ�ʹ��get_bad_stack�����cpsr���������ж�ʱ��cpsrֵ
				// 52��56��60��64��ӦS_SP��S_LR��S_PC��S_PSR

	/* save current stack into r0 (param register) */
	mov	r0, sp
	.endm

	.macro get_bad_stack
	/* setup our mode stack (enter in banked mode) */
	ldr	r13, _armboot_start
	/* move past malloc pool */
	sub	r13, r13, #(CONFIG_SYS_MALLOC_LEN)
	/* move to reserved a couple spots for abort stack */
	sub	r13, r13, #(CONFIG_SYS_GBL_DATA_SIZE + 8)

	/* save caller lr in position 0 of saved stack */
	str	lr, [r13]
	/* get the spsr */
	mrs	lr, spsr
	/* save spsr in position 1 of saved stack */
	str	lr, [r13, #4]

	/* prepare SVC-Mode */
	mov	r13, #MODE_SVC
	@ msr	spsr_c, r13
	/* switch modes, make sure moves will execute */
	msr	spsr, r13
	/* capture return pc */
	mov	lr, pc
	/* jump to next instruction & switch modes. */
	movs	pc, lr
	.endm

	.macro get_bad_stack_swi
	/* space on current stack for scratch reg. */
	sub	r13, r13, #4
	/* save R0's value. */
	str	r0, [r13]
	/* get data regions start */
	ldr	r0, _armboot_start
	/* move past malloc pool */
	sub	r0, r0, #(CONFIG_SYS_MALLOC_LEN)
	/* move past gbl and a couple spots for abort stack */
	sub	r0, r0, #(CONFIG_SYS_GBL_DATA_SIZE + 8)
	/* save caller lr in position 0 of saved stack */
	str	lr, [r0]
	/* get the spsr */
	mrs	r0, spsr
	/* save spsr in position 1 of saved stack */
	str	lr, [r0, #4]
	/* restore r0 */
	ldr	r0, [r13]
	/* pop stack entry */
	add	r13, r13, #4
	.endm

/*
 * exception handlers
 */
	.align	5
undefined_instruction:
	get_bad_stack
	bad_save_user_regs
	bl	do_undefined_instruction

	.align	5
software_interrupt:
	get_bad_stack_swi
	bad_save_user_regs
	bl	do_software_interrupt

	.align	5
prefetch_abort:
	get_bad_stack
	bad_save_user_regs
	bl	do_prefetch_abort

	.align	5
data_abort:
	get_bad_stack
	bad_save_user_regs
	bl	do_data_abort

	.align	5
not_used:
	get_bad_stack
	bad_save_user_regs
	bl	do_not_used

	.align	5
irq:
	get_bad_stack
	bad_save_user_regs
	bl	do_irq

	.align	5
fiq:
	get_bad_stack
	bad_save_user_regs
	bl	do_fiq
#endif /* CONFIG_NAND_SPL */