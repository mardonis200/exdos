
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;									;;
;; ExDOS -- Extensible Disk Operating System				;;
;; Version 0.1 pre alpha						;;
;; Copyright (C) 2015 by Omar Mohammad, all rights reserved.		;;
;;									;;
;; kernel/pci.asm							;;
;; PCI Bus Enumerator							;;
;;									;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use32

is_there_pci			db 0

; init_pci:
; Initializes the legacy PCI Bus

init_pci:
	call go16

use16

	mov eax, 0xB101			; check for PCI BIOS
	mov edi, 0
	int 0x1A
	jc .no_pci			; if there is no PCI BIOS, there may or may not be a PCI bus installation
					; just to be safe, we'll throw an error if PCI BIOS is not supported

	cmp ah, 0
	jne .no_pci

	cmp edx, 0x20494350
	jne .no_pci

	test al, 1			; make sure PCI supports the 32-bit I/O mechanism (port 0xCF8)
	jz .no_pci

	mov byte[is_there_pci], 1

	call go32

use32

	ret

use16

.no_pci:
	call go32

use32

	mov ebx, 0x333333
	mov cx, 0
	mov dx, 218
	mov esi, 800
	mov edi, 160
	call alpha_fill_rect

	mov esi, .no_pci_msg
	mov bx, 32
	mov cx, 250
	mov edx, 0xDEDEDE
	call print_string_transparent

	mov esi, _boot_error_common
	mov bx, 32
	mov cx, 340
	mov edx, 0xDEDEDE
	call print_string_transparent

	sti
	jmp $

.no_pci_msg			db "Boot error: No proper PCI bus was found onboard.",0
.found_pci			db "FOUND PCI BUS",0

; pci_read_dword:
; Reads a DWORD from the PCI bus
; In\	AL = Bus number
; In\	AH = Device number
; In\	BL = Function
; In\	BH = Offset
; Out\	EAX = DWORD from PCI bus

pci_read_dword:
	mov [.bus], al
	mov [.slot], ah
	mov [.func], bl
	mov [.offset], bh

	mov eax, 0
	mov ebx, 0
	mov al, [.bus]
	shl eax, 16
	mov bl, [.slot]
	shl ebx, 11
	or eax, ebx
	mov ebx, 0
	mov bl, [.func]
	shl ebx, 8
	or eax, ebx
	mov ebx, 0
	mov bl, [.offset]
	and ebx, 0xFC
	or eax, ebx
	mov ebx, 0x80000000
	or eax, ebx

	mov edx, 0xCF8
	out dx, eax

	mov edx, 0xCFC
	in eax, dx

	mov edx, 0
	ret

.tmp				dd 0
.bus				db 0
.func				db 0
.slot				db 0
.offset				db 0

; pci_write_dword:
; Writes a DWORD to the PCI bus
; In\	AL = Bus number
; In\	AH = Device number
; In\	BL = Function
; In\	BH = Offset
; In\	ECX = DWORD to write
; Out\	Nothing

pci_write_dword:
	mov [.bus], al
	mov [.slot], ah
	mov [.func], bl
	mov [.offset], bh
	mov [.dword], ecx

	mov eax, 0
	mov ebx, 0
	mov al, [.bus]
	shl eax, 16
	mov bl, [.slot]
	shl ebx, 11
	or eax, ebx
	mov ebx, 0
	mov bl, [.func]
	shl ebx, 8
	or eax, ebx
	mov ebx, 0
	mov bl, [.offset]
	and ebx, 0xFC
	or eax, ebx
	mov ebx, 0x80000000
	or eax, ebx

	mov edx, 0xCF8
	out dx, eax

	mov eax, [.dword]
	mov edx, 0xCFC
	out dx, eax

	mov edx, 0
	ret

.dword				dd 0
.tmp				dd 0
.bus				db 0
.func				db 0
.slot				db 0
.offset				db 0

; pci_get_device:
; Returns the bus and device number of a specified PCI device
; In\	AH = Class code
; In\	AL = Subclass code
; Out\	AL = Bus number (0xFF if invalid)
; Out\	AH = Device number (0xFF if invalid)
; Out\	BL = Function number (0xFF if invalid)

pci_get_device:
	mov byte[.bus], 0
	mov byte[.device], 0
	mov byte[.function], 0
	mov [.class], ax

.search:
	mov al, [.bus]
	mov ah, [.device]
	mov bl, [.function]
	mov bh, 8
	call pci_read_dword

	cmp eax, 0xFFFFFFFF
	je .next_device

	shr eax, 16

	cmp ax, word[.class]
	je .found_device

	add byte[.function], 1
	cmp byte[.function], 0xFF
	je .next_device

	jmp .search

.next_device:
	mov byte[.function], 0
	add byte[.device], 1
	cmp byte[.device], 0xFF
	je .next_bus

	jmp .search

.next_bus:
	mov byte[.device], 0
	add byte[.bus], 1
	cmp byte[.bus], 0xFF
	je .device_not_found

	jmp .search

.found_device:
	mov al, [.bus]
	mov ah, [.device]
	mov bl, [.function]
	and eax, 0xFFFF
	and ebx, 0xFF

	ret

.device_not_found:
	mov eax, 0xFFFF
	mov ebx, 0xFF

	ret

.class				dw 0
.bus				db 0
.device				db 0
.function			db 0

; pci_set_irq:
; Sets the IRQ to be used by a PCI device
; In\	AL = Bus number
; In\	AH = Device number
; In\	BL = Function number
; In\	BH = IRQ to use (0xFF to disable IRQ)
; Out\	Nothing

pci_set_irq:
	mov [.bus], al
	mov [.device], ah
	mov [.function], bl
	mov [.irq], bh
	mov bh, 0x3C
	call pci_read_dword		; read the PCI configuration

	and eax, 0xFFFFFF00		; clear interrupt 
	movzx ebx, [.irq]
	or eax, ebx			; and set the IRQ to be used

	mov ecx, eax
	mov al, [.bus]
	mov ah, [.device]
	mov bl, [.function]
	mov bh, 0x3C
	call pci_write_dword		; write the modified PCI configuration

	ret

.bus				db 0
.device				db 0
.function			db 0
.irq				db 0



