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
/* .balignl是意思是：以当前地址为开始开始，找到第一次出现的以第一个参数(16)为整数倍的地址，并将其作为结束地址，
 *在这个结束地址前面存储4个字节长度的数据，存储内容正是第二个参数。如果当前地址正好是第一个参数的倍数，则没有数
 *据被写入到内存。作用就是为内存做标记，插在那里，就表示从这个位置往后的一段有特殊作用的内存，而这个位置往前，禁止访问。
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
	.word	TEXT_BASE	//在board/samsung/smdk6410/config.mk文件中

/*
 * Below variable is very important because we use MMU in U-Boot.
 * Without it, we cannot run code correctly before MMU is ON.
 * by scsuh.
 */
_TEXT_PHY_BASE:
	.word	CONFIG_SYS_PHY_UBOOT_BASE	//#define CONFIG_SYS_PHY_UBOOT_BASE	(CONFIG_SYS_SDRAM_BASE + 0x07e00000)
						//#define CONFIG_SYS_SDRAM_BASE	0x50000000. 相加结果就是0x57e00000

.globl _armboot_start
_armboot_start:
	.word _start		//_armboot_start中的值就是_start地址(0x0)

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
 * the actual reset code实际的复位代码
 */

reset:
	/*
	 * set the cpu to SVC32 mode(ARM的非特权模式是用户模式，其它模式都是特权模式)
	 *CPSR STATE:
	 *bit[31:8]	 bit7		  bit6		   bit5    	  bit[4:0]
	 * no care    IRQ disable          FIQ disable         Thumb state bit      Mode bits
	 *set cpsr bit[7:0] to 11010011:禁用IRQ/FIQ，设置ARM32指令集状态，SVC模式。
	 */
	mrs	r0, cpsr
	bic	r0, r0, #0x3f
	orr	r0, r0, #0xd3
	msr	cpsr, r0

/*
 *************************************************************************
 *
 * CPU_init_critical registers
 * CPU初始化关键寄存器
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
	 *当从NAND启动时，很明显只是复位，就不用把清除caches和禁用MMU了。
	 */
#ifndef CONFIG_NAND_SPL		//没有找到define!
				//nand_spl/board/samsung/smdk6410/Makefile中有CONFIG_NAND_SPL = y
	/*
	 * flush v4 I/D caches
	 */
	mov	r0, #0
	mcr	p15, 0, r0, c7, c7, 0	/* flush v3/v4 cache.禁用数据、指令cache,清除branch target cache与Branch Target Address Cache(BTAC) */
	mcr	p15, 0, r0, c8, c7, 0	/* flush v4 TLB */

	/*
	 * disable MMU stuff and caches
	 */
	mrc	p15, 0, r0, c1, c0, 0	/* 读c1的内容到r0寄存器.Read Control Register configuration data */
	bic	r0, r0, #0x00002300	@ clear bits 13, 9:8 (--V- --RS)
	bic	r0, r0, #0x00000087	@ clear bits 7, 2:0 (B--- -CAM)
	orr	r0, r0, #0x00000002	/* set bit 1 (A) Align	 对齐错误检查使能 Strict alignment fault checking enabled.*/
	orr	r0, r0, #0x00001000	/* set bit 12 (I) I-Cache  指令catch使能。Instruction Cache enabled */
	/* Prepare to disable the MMU */
	adr	r1, mmu_disable_phys	/* 取得标号基于PC的地址值，存到r1中，因为是字对齐，可以在基于PC值的-1020~1020(-2^10~2^10)范围内寻址 */
	/* We presume we're within the first 1024 bytes */
	and	r1, r1, #0x3fc		//r1&0b11 1111 1100,只取末尾10位(字对齐，最末2位为0)这个偏移地址
	ldr	r2, _TEXT_PHY_BASE	//取得标号的处存储的数据，存到r2中。这个数据是0x57e00000，所以r2=0x57e00000
	ldr	r3, =0xfff00000		//立即数
	and	r2, r2, r3		//r2低20位清0(1M)，本来就是0!高位又不变，这行到底要干嘛....
	orr	r2, r2, r1		//r2=0x57e00000|(r1&0x3fc)=0x57e003fc，这是在为后面程序计数器PC跳转做准备。
					//这个地址是mmu_disable_phys，但0x57e003fc在mDDR中的(在没有使用MMU时)啊。。。
	b	mmu_disable

	.align 5	//ARM的.align 5就是2的5次方对齐，也就是4字节对齐.
	/* Run in a single cache-line */
mmu_disable:
	mcr	p15, 0, r0, c1, c0, 0	//把r0写到c1中去，禁用mmu
	nop
	nop
	mov	pc, r2					//到r2=0x57e00000+(r1&0x3fc)=0x57e003fc地址执行程序。这是在哪里???
							//这个地址是mmu_disable_phys，但0x57e003fc在mDDR中，现在还没有初始化mDDR呢啊。。。
#endif

mmu_disable_phys:			//初始化硬件(外设)
	/* Peri port setup */
	ldr	r0, =0x70000000
	orr	r0, r0, #0x13
	mcr	p15,0,r0,c15,c2,4       @ 256M (0x70000000 - 0x7fffffff)

	/*
	 * Go setup Memory and board specific bits prior to relocation.
	 */
	//关看门狗、清GPIO第0组中断、清所有向量中断、设置中断为IRQ模式(而非FIQ模式)、清中断服务、初始化了时钟、初始化调试串口(UART0)、
	//Nandflash、内存(mDDR)、Wakeup support。
	bl	lowlevel_init		/* go setup pll,mux,memory */

after_copy:
//#ifdef CONFIG_ENABLE_MMU	//不执行!uboot\board\samsung\smdk6410\config.mk,TEXT_BASE = $(RAM_TEXT),$(RAM_TEXT)=0x57e00000.
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
//	bic	r0, r0, r2	//mmu_table高12位清0
//	orr	r1, r0, r1	//高12位置为0x57ex_xxxx
//	mcr	p15, 0, r1, c2, c0, 0	//Holds the translation table base address, the physical address of the first
					//level translation table. The reset value is 0.

	/* Enable the MMU */
//	mrc	p15, 0, r0, c1, c0, 0	//Read Control Register configuration data to r0.
//	orr	r0, r0, #1		/* Set CR_M to enable MMU */

	/* Prepare to enable the MMU */
//	adr	r1, skip_hw_init
//	and	r1, r1, #0x3fc
//	ldr	r2, _TEXT_BASE		//在board/samsung/smdk6410/config.mk文件中,默认应该没有开MMU功能
//	ldr	r3, =0xfff00000
//	and	r2, r2, r3
//	orr	r2, r2, r1		//0x57e003fc或0xc7e003fc
//	b	mmu_enable

//	.align 5	//2^5 bit align, means 4 Byte align
	/* Run in a single cache-line */
//mmu_enable:
//
//	mcr	p15, 0, r0, c1, c0, 0	//r0的第0位==1，其余为原c1中的值
//	nop
//	nop
//	mov	pc, r2			////0x57e003fc或0xc7e003fc,如果使能了MMU，则应该为后者
//#endif

skip_hw_init:
	/* Set up the stack */
stack_setup:
	/* 如果MMU使能了，CONFIG_SYS_UBOOT_BASE就是0xc7e0_0000,否则就是0x57e0_0000 */
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

#ifndef CONFIG_NAND_SPL		//没有找到define!执行!
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
	ldr	r4, _TEXT_PHY_BASE	//取得标号的处存储的数据，存到r2中。这个数据是0x57e00000，所以r2=0x57e00000
	adr	r5, phy_last_jump
	bic	r5, r5, r3
	orr	r5, r5, r4
	mov	pc, r5		//高12位改为0x57e
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
	/* carve out/开拓/ a frame on current user stack */
	sub	sp, sp, #S_FRAME_SIZE	//S_FRAME_SIZE=72
	/* Save user registers (now in svc mode) r0-r12 */
	stmia	sp, {r0 - r12}	//ia: increase after, sp=sp+4*13-4.如果sp后带!，则sp=sp+4*13
				// 要注意的是，这句指令执行完后，sp的值又恢复成原值，就是“sub sp, sp, #S_FRAME_SIZE”后的值(不对，因为sp后没有!号。)

	ldr	r2, _armboot_start	//r2=_start地址存储的内容,要分析一下,应该是0x57e00000
	sub	r2, r2, #(CONFIG_SYS_MALLOC_LEN)//CFG_MALLOC_LEN是堆的大小,CONFIG_STACKSIZE是正常程序运行时的栈大小
	/* set base 2 words into abort stack */
	sub	r2, r2, #(CONFIG_SYS_GBL_DATA_SIZE+8)// CFG_GBL_DATA_SIZE是一个全局变量的大小，8：两个字，用来存放发生这些异常时的pc、cpsr寄存器
	/* get values for "aborted" pc and cpsr (into parm regs) */
	ldmia	r2, {r2 - r3}	// 把发生异常时，使用get_bad_stack保存的pc、cpsr寄存器加载到r2,r3

	/* grab pointer to old stack */
	add	r0, sp, #S_FRAME_SIZE	 // r0=原来的SP值

	add	r5, sp, #S_SP	// 从这句指令看，原来SP之上，也是用来保存寄存器的,S_SP=52，表示“原来SP + 52”的地方，是保存sp寄存器
	mov	r1, lr
	/* save sp_SVC, lr_SVC, pc, cpsr */
	stmia	r5, {r0 - r3}	//“原来SP + 52”的地方 存入 r0，即“原来的SP值”，就是sp_SVC，即被中断时的SP值
				// “原来SP + 56”的地方 存入 r1，即lr，就是lr_SVC，即被中断时的lr值
				// “原来SP + 60”的地方 存入 r2，即pc，就是“使用get_bad_stack保存的pc”，即被中断时的pc值
				// “原来SP + 64”的地方 存入 r3，即cpsr，就是“使用get_bad_stack保存的cpsr”，即被中断时的cpsr值
				// 52、56、60、64对应S_SP、S_LR、S_PC、S_PSR

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
