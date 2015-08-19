
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;									;;
;; ExDOS -- Extensible Disk Operating System				;;
;; Version 0.1 pre alpha						;;
;; Copyright (C) 2015 by Omar Mohammad, all rights reserved.		;;
;;									;;
;; kernel/os_api.asm							;;
;; Kernel API								;;
;;									;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

use32

os_api_max_function			= 42

; os_api:
; Kernel API Entry Point
; In\	EAX = Function number
; In\	All other registers = Depends on function input
; Out\	All registers = Depends on function output

os_api:
	pusha
	call enter_ring0		; ensure the API runs in ring 0
	popa

	sti

	pusha
	cmp eax, os_api_max_function
	jg .bad
	popa

	pusha
	mov ebx, 4
	mul ebx
	mov edi, os_api_table
	add edi, eax
	mov eax, dword[edi]
	mov [.tmp], eax
	popa

	mov eax, [.tmp]
	call eax

	pusha
	call enter_ring3		; ensure we continue execution in user mode
	popa
	ret

.bad:
	popa
	call enter_ring3
	mov eax, 0xBADFBADF
	ret

.tmp			dd 0

; os_api_table:
; Call table for API functions

os_api_table:
	; Core routines
	dd execute_program			; 0
	dd mem_info				; 1
	dd kernel_info				; 2
	dd kdebug_get_location			; 3

	; Display routines
	dd clear_screen				; 4
	dd print_string_graphics_cursor		; 5
	dd print_string_graphics		; 6
	dd print_string_transparent		; 7
	dd move_cursor_graphics			; 8
	dd put_pixel				; 9
	dd draw_horz_line			; 10
	dd fill_rect				; 11
	dd alpha_draw_horz_line			; 12
	dd alpha_fill_rect			; 13
	dd alpha_blend_colors			; 14
	dd draw_image				; 15
	dd get_screen_info			; 16
	dd hide_text_cursor			; 17
	dd show_text_cursor			; 18

	; Keyboard routines
	dd get_char_wait			; 19
	dd get_char_no_wait			; 20
	dd get_string_echo			; 21

	; String-based routines
	dd get_string_size			; 22
	dd chomp_string				; 23
	dd .int_to_string			; 24
	dd .hex_byte_to_string			; 25
	dd .hex_word_to_string			; 26
	dd .hex_dword_to_string			; 27
	dd compare_strings			; 28

	; Power-based routines
	dd reboot				; 29
	dd shutdown				; 30

	; Time-based routines
	dd get_time_24				; 31
	dd get_time_12				; 32
	dd get_time_string_24			; 33
	dd get_time_string_12			; 34
	dd get_date				; 35
	dd get_date_string_am			; 36
	dd get_date_string_me			; 37
	dd get_long_date_string			; 38

	; Mouse routines
	dd get_mouse_status			; 39
	dd show_mouse_cursor			; 40
	dd hide_mouse_cursor			; 41
	dd set_mouse_cursor			; 42


.int_to_string:
	mov eax, ebx
	call int_to_string
	ret

.hex_byte_to_string:
	mov eax, ebx
	call hex_byte_to_string
	ret

.hex_word_to_string:
	mov eax, ebx
	call hex_word_to_string
	ret

.hex_dword_to_string:
	mov eax, ebx
	call hex_dword_to_string
	ret

; mem_info:
; Gets memory information
; In\	Nothing
; Out\	EAX = Total memory in KB
; Out\	EBX = Free memory in KB
; Out\	ECX = Used memory in KB

mem_info:
	mov eax, [free_memory]
	mov ebx, 4
	mul ebx
	mov [.free], eax
	mov eax, [used_memory]
	mov ebx, 4
	mul ebx
	mov [.used], eax
	mov eax, [total_memory_kb]
	mov ebx, [.free]
	mov ecx, [.used]

	ret

.used			dd 0
.free			dd 0

; kernel_info:
; Gets kernel information
; In\	Nothing
; Out\	ESI = Kernel version string
; Out\	EAX = API version

kernel_info:
	mov esi, _kernel_version
	mov eax, [_api_version]

	ret

