
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;									;;
;; ExDOS -- Extensible Disk Operating System				;;
;; Version 0.1 pre alpha						;;
;; Copyright (C) 2015-2016 by Omar Mohammad, all rights reserved.	;;
;;									;;
;; kernel/kernel.asm							;;
;; ExDOS Kernel Entry Point						;;
;;									;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; The first part of the kernel is a 16-bit stub.
; It uses BIOS to do several tasks, such as enabling A20, detecting memory, getting keyboard input...
; It also prompts the user for the resolution they want to use.

use16
org 0x500

jmp 0:kmain16

use32
align 32

jmp os_api

use16

define TODAY "Saturday, 2nd January, 2016"

_kernel_version			db "ExDOS v0.1.0 pre-alpha built ", TODAY, 0
_crlf				db 13,10,0

syswidth			dw 0
sysheight			dw 0
sysbpp				db 0

api_version			= 1
stack_size			= 4096				; reserve 4 KB of stack space

kmain16:
	cli
	cld
	mov ax, 0
	mov es, ax

	mov di, boot_partition
	mov cx, 16
	rep movsb

	mov ax, 0
	mov ss, ax
	mov ds, ax
	mov fs, ax
	mov gs, ax
	mov sp, stack_area+stack_size

	sti

	mov [bootdisk], dl

	mov si, _kernel_version
	call print_string_16

	mov si, _crlf
	call print_string_16

	mov ax, 0x1100
	mov bp, font_data
	mov cx, 0x100
	mov dx, 0
	mov bl, 0
	mov bh, 16
	int 0x10

	call enable_a20				; enable A20 gate
	call check_a20				; check A20 status
	call detect_memory			; detect memory using E820, and use E801 if E820 fails
	call verify_enough_memory		; verify we have enough usable RAM
	;call check_vbe				; check for VESA BIOS

get_vesa_mode_loop:
	mov byte[is_paging_enabled], 0

	mov ax, 0x1100
	mov bp, font_data
	mov cx, 0x100
	mov dx, 0
	mov bl, 0
	mov bh, 16
	int 0x10

	mov si, _crlf
	call print_string_16

	mov si, .msg
	call print_string_16

.loop:
	mov ax, 0
	int 0x16

	cmp al, 13
	je .loop

	cmp al, 8
	je .loop

	push ax
	mov ah, 0xE
	int 0x10
	mov ah, 0xE
	mov al, 8
	int 0x10
	pop ax

	cmp al, '1'
	je .640x480

	cmp al, '2'
	je .800x600

	cmp al, '3'
	je .1024x768

	cmp al, '4'
	je .1366x768

	cmp al, '5'
	je .1024x600

	jmp .loop

.640x480:
	mov [syswidth], 640
	mov [sysheight], 480
	jmp .set_mode

.800x600:
	mov [syswidth], 800
	mov [sysheight], 600
	jmp .set_mode

.1024x768:
	mov [syswidth], 1024
	mov [sysheight], 768
	jmp .set_mode

.1366x768:
	mov [syswidth], 1366
	mov [sysheight], 768
	jmp .set_mode

.1024x600:
	mov [syswidth], 1024
	mov [sysheight], 600

.set_mode:
	jmp check_serial_loop

.error:
	mov ax, 3
	int 0x10

	mov si, _crlf
	call print_string_16

	mov si, .bad_resol_msg
	call print_string_16

	jmp get_vesa_mode_loop

.msg			db "Select your preferred screen resolution: ",13,10
			db " [1] 640x480",13,10
			db " [2] 800x600",13,10
			db " [3] 1024x768",13,10
			db " [4] 1366x768",13,10
			db " [5] 1024x600",13,10
			db "Your choice: ",0
.bad_resol_msg		db "This resolution is not supported by your graphics card or your display.",13,10
			db "Please try another resolution.",13,10,0

check_serial_loop:
	mov si, _crlf
	call print_string_16
	mov si, _crlf
	call print_string_16

	mov si, .msg
	call print_string_16

.loop:
	mov ax, 0
	int 0x16

	cmp al, 13
	je .loop

	cmp al, 8
	je .loop

	push ax
	mov ah, 0xE
	int 0x10
	mov ah, 0xE
	mov al, 8
	int 0x10
	pop ax

	cmp al, 'y'
	je .yes

	cmp al, 'Y'
	je .yes

	cmp al, 'n'
	je .no

	cmp al, 'N'
	je .no

	jmp .loop

.yes:
	mov byte[serial_enabled], 1
	jmp enter_pmode

.no:
	mov byte[serial_enabled], 0
	jmp enter_pmode

.msg			db "Should the kernel debug messages be forwarded to serial port? (y/N)",13,10
			db "Your choice: ",0
serial_enabled		db 0
hardware_bitflags	dw 0

enter_pmode:
	mov eax, 0
	int 0x11				; detect hardware
	mov [hardware_bitflags], ax

	mov eax, 0xEC00
	mov ebx, 1
	int 0x15				; notify the BIOS we're going to run in protected mode

	cli
	lgdt [gdtr]
	lidt [idtr]

	mov eax, cr0
	or eax, 1				; enable protected mode
	mov cr0, eax

	jmp 8:kmain32

use32

kmain32:
	cli
	mov ax, 0x10
	mov ss, ax
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	movzx esp, sp

	pushfd
	pop eax
	and eax, 0xFFFFCFFF			; prevent v8086 from doing CLI/STI, and only the kernel can do IN/OUT
	push eax
	popfd

	call init_serial			; enable serial port
	call kdebug_init			; initialize kernel debugger
	call init_exceptions			; we should install exceptions handlers before anything, just to be safe

	mov al, 0x20
	mov ah, 0x28
	call remap_pic

	call init_sse_avx			; enable SSE or AVX, based on what is available on the CPU
	call pmm_init				; initalize physical memory manager
	call vmm_init				; start paging and virtual memory management
	call init_pit				; set up PIT to 100 Hz
	call init_kbd				; initialize PS/2 keyboard
	call init_pci				; initialize legacy PCI

	mov ax, [syswidth]
	mov bx, [sysheight]
	mov cl, 32
	call set_vesa_mode			; set 32bpp VESA mode

	cmp eax, 0				; if that didn't work, try doing it with 24 bpp
	jne .try_24bpp

	jmp .draw_boot_screen

.try_24bpp:
	mov ax, [syswidth]
	mov bx, [sysheight]
	mov cl, 24
	call set_vesa_mode

	cmp eax, 0
	jne .vesa_error

	jmp .draw_boot_screen

.vesa_error:
	call go16

use16

	jmp get_vesa_mode_loop.error

use32

.draw_boot_screen:
	mov ebx, 0
	call clear_screen

	;call enable_mtrr_framebuffer		; at the moment this caused loss of performance, I don't know why...
	call avx_debug				; for debugging...
	call init_hdd				; initialize hard disk
	call init_edd_info			; get EDD BIOS info
	call detect_exdfs			; verify the partition is formatted with ExDFS
	call show_detected_hardware		; show INT 0x11 detected hardware
	call init_sysenter			; initialize SYSENTER/SYSEXIT MSRs
	call load_tss				; load the TSS
	call init_cpuid				; get CPU brand
	call detect_cpu_speed			; get CPU speed
	call init_acpi				; initialize ACPI
	call init_acpi_power			; initialize ACPI power management
	call init_cmos				; initialize CMOS RTC clock
	;call init_pcie				; PCI Express is not yet implemented
	;call ata_init				; initialize IDE ATA controller
	;call ahci_init				; initialize SATA (AHCI) controller
	call init_mouse				; initialize PS/2 mouse

	sti

	;call run_v8086				; for debugging...

	mov esi, init_filename
	call execute_program
	jmp panic_no_processes

avx_debug:
	cmp byte[is_avx_supported], 1
	je .avx

	mov esi, .sse_msg
	mov ecx, 0
	mov edx, 0xFFFFFF
	call print_string_graphics_cursor

	ret

.avx:
	mov esi, .avx_msg
	mov ecx, 0
	mov edx, 0xFFFFFF
	call print_string_graphics_cursor

	ret

.sse_msg			db "CPU supports SSE; using it.",10,0
.avx_msg			db "CPU supports AVX; using it.",10,0

init_filename			db "init.exe",0

include				"kernel/stdio.asm"		; Standard I/O
include				"kernel/string.asm"		; String manipulation routines
include				"kernel/serial.asm"		; Serial port driver
include				"kernel/system.asm"		; Internal system routines
include				"kernel/isr.asm"		; Interrupt service routines
include				"kernel/vesa.asm"		; VESA 2.0 framebuffer driver
include				"kernel/kbd.asm"		; Keyboard driver
include				"kernel/font.asm"		; Bitmap font
include				"kernel/gdi.asm"		; Graphical device interface
include				"kernel/hdd.asm"		; Hard disk "driver"
include				"kernel/cmos.asm"		; CMOS RTC driver
include				"kernel/cpuid.asm"		; CPUID parser
include				"kernel/panic.asm"		; Kernel panic screen
include				"kernel/power.asm"		; Basic power management
include				"kernel/pmm.asm"		; Physical memory manager
include				"kernel/vmm.asm"		; Virtual memory manager
include				"kernel/tasking.asm"		; Multitasking
include				"kernel/v8086.asm"		; v8086 monitor
include				"kernel/exdfs.asm"		; ExDFS driver
include				"kernel/api.asm"		; Kernel API
;include			"kernel/pcie.asm"		; PCI Express enumerator
include				"kernel/pci.asm"		; PCI enumerator
include				"kernel/acpi.asm"		; ACPI driver
include				"kernel/apm.asm"		; APM BIOS
;include			"kernel/ata.asm"		; ATA disk driver
;include			"kernel/ahci.asm"		; SATA (AHCI) disk driver
include				"kernel/drivers.asm"		; Driver interface
include				"kernel/kdebug.asm"		; Kernel debugger
include				"kernel/booterror.asm"		; Boot error UI
include				"kernel/mouse.asm"		; PS/2 mouse driver
include				"kernel/math.asm"		; Math routines
include				"kernel/sound.asm"		; PC speaker driver

db				"This program is property of Omar Mohammad.",0

align 4096			; stack will be in its own page so we can map it as read/write

stack_area:			rb stack_size			; 4 KB of stack space
kstack_area:			rb 256

align 32

memory_map:
disk_buffer:							; reserve whatever is left in memory as a disk buffer



