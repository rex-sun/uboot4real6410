/*
 * Memory Setup stuff - taken from blob memsetup.S
 *
 * Copyright (C) 1999 2000 2001 Erik Mouw (J.A.K.Mouw@its.tudelft.nl) and
 *		       Jan-Derk Bakker (J.D.Bakker@its.tudelft.nl)
 *
 * Modified for the Samsung SMDK2410 by
 * (C) Copyright 2002
 * David Mueller, ELSOFT AG, <d.mueller@elsoft.ch>
 *
 * (C) Copyright 2008
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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston,
 * MA 02111-1307 USA
 */


#include <config.h>
#include <version.h>

#include <asm/arch/s3c6410.h>

#ifdef CONFIG_SERIAL1	//defined in file include/configs/smdk6410.h，使用串口1(UART0)作为调试用
#define ELFIN_UART_CONSOLE_BASE (ELFIN_UART_BASE + ELFIN_UART0_OFFSET)	//0x7f00_5000->ULCON0
#elif defined(CONFIG_SERIAL2)		//未定义，不执行
#define ELFIN_UART_CONSOLE_BASE (ELFIN_UART_BASE + ELFIN_UART1_OFFSET)	//不执行
#else	
#define ELFIN_UART_CONSOLE_BASE (ELFIN_UART_BASE + ELFIN_UART2_OFFSET)	//不执行
#endif

_TEXT_BASE:
	.word	TEXT_BASE	//0x57e00000或者0.

.globl	lowlevel_init

lowlevel_init:
	mov	r12, lr	//lr是r14，保存链接地址，用于程序返回时跳转

	/* LED on only #8 确保编译的uboot的可以在板子上跑起来，那就点亮LED1确认一下吧*/
	ldr	r0, =ELFIN_GPIO_BASE
	ldr	r1, =0x111111		//GPL13-GPL8:0001:output,GPL14:NC
	str	r1, [r0, #GPLCON1_OFFSET]

	ldr	r1, =0x4000000		//@ Enable GPL13 Pull-down,other disabled。如果设置了GPLDAT输出0，就不要选上拉enable了。
	str	r1, [r0, #GPLPUD_OFFSET]

	ldr	r1, =0x0		//Output 0
	str	r1, [r0, #GPLDAT_OFFSET]

	//1.关看门狗
	/* Disable Watchdog */
	ldr	r0, =0x7e000000		@WTCON 0x7e004000
	orr	r0, r0, #0x4000
	mov	r1, #0
	str	r1, [r0]

	//2.清GPIO中断，只清了第0组(EINT0)
	/* External interrupt pending clear:对于GPIO中断，只清了第0组(EINT0)的pending bit */
	ldr	r0, =(ELFIN_GPIO_BASE+EINTPEND_OFFSET)	/*EINTPEND*/
	ldr	r1, [r0]
	str	r1, [r0]	// 方法:0 = Not occur, 1= Occur interrupt, "Each bit is cleared by writing "1""

	//3.清所有向量中断
	ldr	r0, =ELFIN_VIC0_BASE_ADDR	@0x71200000
	ldr	r1, =ELFIN_VIC1_BASE_ADDR	@0x71300000

	/* Disable all interrupts (VIC0 and VIC1) */
	mvn	r3, #0x0	//r3=0xffffffff
	str	r3, [r0, #oINTMSK]	//VIC0INTENCLEAR register, set 1 to clear corresponding bits in the VICINTENABLE Register.
	str	r3, [r1, #oINTMSK]	//VIC1INTENCLEAR register, set 1 to clear corresponding bits in the VICINTENABLE Register.

	//4.设置所有中断为IRQ模式(而非FIQ模式)
	/* Set all interrupts as IRQ */
	mov	r3, #0x0
	str	r3, [r0, #oINTMOD]	//VIC0INTSELECT:Selects type of interrupt for interrupt request:0 = IRQ interrupt (reset), 1= FIQ interrupt
	str	r3, [r1, #oINTMOD]	//VIC1INTSELECT:Selects type of interrupt for interrupt request:0 = IRQ interrupt (reset), 1= FIQ interrupt

	//5.清除所有中断,包括等待服务中的中断
	/* Pending Interrupt Clear */
	/* Contains the address of the currently active ISR
	 * A read of this register returns the address of the ISR and sets the current interrupt as being serviced. A read must only be performed while
	 *there is an active interrupt.A write of any value to this register clears the current interrupt. A write must only be performed at the end of
	 *an interrupt service routine.
	 */
	mov	r3, #0x0
	str	r3, [r0, #oVECTADDR]	
	str	r3, [r1, #oVECTADDR]
	//6.初始化时钟
	/* init system clock */
	bl system_clock_init

#ifndef CONFIG_NAND_SPL	//没有看到define!执行
	/* for UART */
	bl uart_asm_init	//设置GPIO A,初始化调试串口(UART0)
#endif

#ifdef CONFIG_BOOT_NAND		//在include/configs/smdk6410.h中define 了它。
	/* simple init for NAND */
	bl nand_asm_init	//初始化NandFlash并使能
#endif

	/* Memory subsystem address 0x7e00f120 */
	ldr	r0, =ELFIN_MEM_SYS_CFG

	/* Xm0CSn2 = NFCON CS0, Xm0CSn3 = NFCON CS1 */
	mov	r1, #S3C64XX_MEM_SYS_CFG_NAND	//此处做过更改，又改回去了
	str	r1, [r0]

	bl	mem_ctrl_asm_init	//defined in cup_init.S

/* Wakeup support. Don't know if it's going to be used, untested. */
	ldr	r0, =(ELFIN_CLOCK_POWER_BASE + RST_STAT_OFFSET)
	ldr	r1, [r0]
	bic	r1, r1, #0xfffffff7	//为什么这个立即数是合法的???
	cmp	r1, #0x8
	beq	wakeup_reset

1:
	mov	lr, r12
	mov	pc, lr	//返回到start.S

wakeup_reset:

	/* Clear wakeup status register */
	ldr	r0, =(ELFIN_CLOCK_POWER_BASE + WAKEUP_STAT_OFFSET)
	ldr	r1, [r0]
	str	r1, [r0]

	/* LED test : kill LED1*/
	ldr	r0, =ELFIN_GPIO_BASE
	ldr	r1, =0x2000
	str	r1, [r0, #GPLDAT_OFFSET]

	/* Load return address and jump to kernel */
	ldr	r0, =(ELFIN_CLOCK_POWER_BASE + INF_REG0_OFFSET)	//User defined information. INFORM0~3 registers are cleared by asserting XnRESET pin. 
	/* r1 = physical address of s3c6410_cpu_resume function */
	ldr	r1, [r0]
	/* Jump to kernel (sleep-s3c6410.S) */
	mov	pc, r1
	nop
	nop
/*
 * system_clock_init: Initialize core clock and bus clock.
 * void system_clock_init(void)
 */
system_clock_init:
	ldr	r0, =ELFIN_CLOCK_POWER_BASE	/* 0x7e00f000 */

#ifdef CONFIG_SYNC_MODE		//not defined(in file: include/configs/smdk6410.h)--下面代码段是不执行的
	ldr	r1, [r0, #OTHERS_OFFSET]
	mov	r2, #0x40	
	orr	r1, r1, r2	//bit[6]SYS CLOCK SELECT IN CMU: 0:MOUT_MPLL,1:DOUT_APLL
	str	r1, [r0, #OTHERS_OFFSET]

	nop
	nop
	nop
	nop
	nop
	/* set synchronous mode */
	ldr	r2, =0x80
	orr	r1, r1, r2	//bit[7]:SYNCMODEREQ to ARM:0: Asynchronous mode, 1: Synchronous mode, 据说，当CPU时钟(ARMCLK) != 内存时钟(HCLK)时，要设为异步模式。
	str	r1, [r0, #OTHERS_OFFSET]

check_syncack:
	ldr	r1, [r0, #OTHERS_OFFSET]
	ldr	r2, =0xf00
	and	r1, r1, r2
	cmp	r1, #0xf00
	bne	check_syncack
#else	/* ASYNC Mode :实际跑的是ASYNC MODE*/
	nop
	nop
	nop
	nop
	nop

	/*
	 * This was unconditional in original Samsung sources, but it doesn't
	 * seem to make much sense on S3C6410.
	 */
#ifndef CONFIG_S3C6410		//defined in include/configs/smdk6410.h--下面代码段是不执行的
	ldr	r1, [r0, #OTHERS_OFFSET]
	bic	r1, r1, #0xC0	//bit[7]:SYNCMODEREQ to ARM:0: Asynchronous mode, 1: Synchronous mode, 据说，当CPU时钟(ARMCLK) != 内存时钟(HCLK)时，要设为异步模式。
	orr	r1, r1, #0x40
	str	r1, [r0, #OTHERS_OFFSET]

wait_for_async:
	ldr	r1, [r0, #OTHERS_OFFSET]
	and	r1, r1, #0xf00
	cmp	r1, #0x0
	bne	wait_for_async
#endif

	ldr	r1, [r0, #OTHERS_OFFSET]
	bic	r1, r1, #0x40		//bit[6]SYS CLOCK SELECT IN CMU: 0:MOUT_MPLL,1:DOUT_APLL.系统时钟源设为0:MOUT_MPLL,为什么不在上边wait_for_async那里一起设置呢?
					//因为上边那里是不执行的。而bit[7]=0是reset_value.所以这里就设置成了异步模式(ASYNC MODE)、并设置MOUT_MPLL为系统时钟。
	str	r1, [r0, #OTHERS_OFFSET]
#endif

	mov	r1, #0xff	//更改
	orr	r1, r1, #0xff		//Why set in 2 lines?是因为一条汇编指令处理不了这个立即数，
					//ARM汇编能处理的立即数是那些能够由8位立即数循环右移偶数位(0,2,4,6,...,28,30)得到的得到的。
	str	r1, [r0, #APLL_LOCK_OFFSET]	//Required period to generate a stable clock output 
	str	r1, [r0, #MPLL_LOCK_OFFSET]	//Required period to generate a stable clock output 

	/* Set Clock Divider */
	ldr	r1, [r0, #CLK_DIV0_OFFSET]
	bic	r1, r1, #0x30000	//bit[17:16]=00
	bic	r1, r1, #0xff00		//bit[15:8]=00000000
	bic	r1, r1, #0xff		//bit[7:0]=0000000
	ldr	r2, =CLK_DIV_VAL	//MPLLDIV为1(裸板时为0)，设置不一样之处。不过这只影响DOUT_MPLL，对ACLK/HCLK/PCLK无影响。
	orr	r1, r1, r2
	str	r1, [r0, #CLK_DIV0_OFFSET]

	ldr	r1, =APLL_VAL
	str	r1, [r0, #APLL_CON_OFFSET]
	ldr	r1, =MPLL_VAL
	str	r1, [r0, #MPLL_CON_OFFSET]

	/* FOUT of EPLL is 96MHz */
//	ldr	r1, =0x80200203		//而0x80200203:MDIV=32,PDIV=2,SDIV=3.这里应该是原作者写错了。
	ldr	r1, =0x80200102		//96MHz应该为:0x80200102:MDIV=32,PDIV=1,SDIV=2,KDIV=0,bit[31]=1:PLL enable
	str	r1, [r0, #EPLL_CON0_OFFSET]
	ldr	r1, =0x0
	str	r1, [r0, #EPLL_CON1_OFFSET]

	/* APLL, MPLL, EPLL select to Fout */
	ldr	r1, [r0, #CLK_SRC_OFFSET]
	orr	r1, r1, #0x7
	str	r1, [r0, #CLK_SRC_OFFSET]

	/* wait at least 200us to stablize all clock */
	mov	r1, #0x10000
1:	subs	r1, r1, #1
	bne	1b	//怎么冒出来个1b呢?

	/* Synchronization for VIC port */
#if defined(CONFIG_SYNC_MODE)		//not defined(in file: include/configs/smdk6410.h)--下面代码段是不执行的
	ldr	r1, [r0, #OTHERS_OFFSET]
	orr	r1, r1, #0x20	//bit[5] 置1??!规格书上要求:bit[5:3],reserved,DO NOT CHANGE, reset value: 0x3
	str	r1, [r0, #OTHERS_OFFSET]
#elif !defined(CONFIG_S3C6410)		//defined in file:include/configs/smdk6410.h.所以下面这一段也不执行。
	/* According to 661558um_S3C6410X_rev10.pdf 0x20 is reserved */
	ldr	r1, [r0, #OTHERS_OFFSET]
	bic	r1, r1, #0x20
	str	r1, [r0, #OTHERS_OFFSET]
#endif
	mov	pc, lr


#ifndef CONFIG_NAND_SPL
/*
 * uart_asm_init: Initialize UART's pins
 */
uart_asm_init:
	/* set GPIO to enable UART */
	ldr	r0, =ELFIN_GPIO_BASE
	ldr	r1, =0x220022	//UART0:GPA0 & GPA1用作调试串口线(Real6410)
	str	r1, [r0, #GPACON_OFFSET]
	mov	pc, lr
#endif

#ifdef CONFIG_BOOT_NAND		//只要#defined了就执行，不管有没有值。这行是不是要放到nand_asm_init:下面去啊??
/*
 * NAND Interface init for SMDK6410
 */
nand_asm_init:
/* Set static memory chip selection multiplexing of memory port 0.*/
	ldr	r0, =ELFIN_CLOCK_POWER_BASE
 	ldr	r1, [r0, #MEM_SYS_CFG_OFFSET]
 	bic	r1, r1, #2
 	str	r1, [r0, #MEM_SYS_CFG_OFFSET]	//Xm0CSn[2]选择NAND Flash,名字中的n表示低电平有效。
 	
	ldr	r0, =ELFIN_NAND_BASE
	ldr	r1, [r0, #NFCONF_OFFSET]
//	orr	r1, r1, #0x70		//这行与下一行的配置，与本机用的板子上的器件不同，所以更改了。
//	orr	r1, r1, #0x7700
//	bic	r1, r1, #0x40007770	//"之前忘记加#表示立即数了!"实际上，立即数是不可以这么用的，不清楚就去查一下"ARM汇编中立即数的要求"吧!!
	ldr	r2, =0x40007770		//=号后边的立即数，前面就不要再加#了!!!
	bic	r1, r1, r2
	orr	r1, r1, #NAND_DUR_VAL	//TACLS /TWRPH0 /TWRPH1 value setting
	str	r1, [r0, #NFCONF_OFFSET]

	ldr	r1, [r0, #NFCONT_OFFSET]
	orr	r1, r1, #0x5	//bit[2]:1-- Force Xm0CSn3 to High(Disable chip select),bit[0]:1-- NAND Flash Controller Enable
	bic	r1, r1, #0x2	//bit[1]:0-- Force Xm0CSn2 to low(Enable chip select).
	str	r1, [r0, #NFCONT_OFFSET]

	mov	pc, lr		//BL指令用MOV  PC,R14(LR) 返回。
#endif

#ifdef CONFIG_ENABLE_MMU	//defined in file: include/configs/smdk6410.h,但是到底用不用MMU，还要看定义处代码，还有其它条件限制呢。
				//这块好像根本没有用到!!
/*
 * MMU Table for SMDK6410
 */

	/* form a first-level section entry */
.macro FL_SECTION_ENTRY base,ap,d,c,b	//宏FL_SECTION_ENTRY根据控制参数建立一个字大小的描述符
	.word (\base << 20) | (\ap << 10) | \
	      (\d << 5) | (1<<4) | (\c << 3) | (\b << 2) | (1<<1)
.endm

.section .mmudata, "a"
	.align 14	//2^14 Bit对齐，就是16KB对齐，P15的C2 register：页表基地址，有效的为[31:14]，所以页表地址必须16KB对齐。
	/* the following alignment creates the mmu table at address 0x4000. */
	.globl mmu_table
mmu_table:		//汇编建表
	.set __base, 0	//__base为这部分代码建表物理地址的基地址，此处设为0是为了调试用。后面设置为0x500
	/* 1:1 mapping for debugging */
	.rept 0xA00
	FL_SECTION_ENTRY __base, 3, 0, 0, 0
	.set __base, __base + 1
	.endr

	/* access is not allowed. */
	.rept 0xC00 - 0xA00
	.word 0x00000000
	.endr

	/* 256MB for SDRAM 0xC0000000 -> 0x50000000 */
	.set __base, 0x500
	.rept 0xD00 - 0xC00		//更改了,由0xC80改为0xD00,256M
	FL_SECTION_ENTRY __base, 3, 0, 1, 1
	.set __base, __base + 1
	.endr

	/* access is not allowed. */
	.rept 0x1000 - 0xd00		//更改了,由0x1000 - 0xc80改为0x1000 - 0xd00
	.word 0x00000000
	.endr
#endif
