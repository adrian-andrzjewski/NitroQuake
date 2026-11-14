.intel_syntax noprefix
.code16
.section .text
.global _start

_start:
	mov ax, cs
	mov ds, ax
	mov es, ax
	mov byte ptr [drive_index], 0

	/* Prefer the current drive, which supports MSCDEX variants without 150B. */
	mov ah, 0x19
	int 0x21
	mov byte ptr [drive_index], al
	call set_disc_paths
	mov dx, offset marker_path
	mov ax, 0x3d00
	int 0x21
	jnc have_disc

	/* Ask MSCDEX before probing any other letter, avoiding empty-drive prompts. */
	mov byte ptr [drive_index], 0
find_cd:
	xor cx, cx
	mov cl, byte ptr [drive_index]
	mov ax, 0x150b
	int 0x2f
	test ax, ax
	jz next_cd
	cmp bx, 0xadad
	jne next_cd
	call set_disc_paths
	mov dx, offset marker_path
	mov ax, 0x3d00
	int 0x21
	jnc have_disc
next_cd:
	inc byte ptr [drive_index]
	cmp byte ptr [drive_index], 26
	jb find_cd
	mov dx, offset no_disc_message
	call print_string
	mov ax, 0x4c02
	int 0x21

have_disc:
	mov bx, ax
	mov ah, 0x3e
	int 0x21
	call scan_output_drives
	jc no_output
	call copy_runtime_files
	jc copy_failed

	/* Start the DPMI application from writable storage so swap files are safe. */
	mov dl, byte ptr [output_index]
	mov ah, 0x0e
	int 0x21
	mov dx, offset output_cwd
	mov ah, 0x3b
	int 0x21
	jc no_output

	/* Keep only this small real-mode stub resident while the menu is running. */
	mov ax, cs
	mov ss, ax
	mov sp, offset stack_top
	mov es, ax
	mov bx, offset program_end
	add bx, 15
	shr bx, 4
	mov ah, 0x4a
	int 0x21
	jc memory_error

	mov ax, cs
	mov word ptr [exec_params + 4], ax
	mov word ptr [exec_params + 6], offset blank_fcb
	mov word ptr [exec_params + 8], ax
	mov word ptr [exec_params + 10], offset blank_fcb
	mov word ptr [exec_params + 12], ax
	mov ds, ax
	mov dx, offset menu_path
	mov ax, cs
	mov es, ax
	mov bx, offset exec_params
	mov ax, 0x4b00
	int 0x21
	jnc exit_ok
	mov dx, offset menu_error_message
	call print_string
	mov ax, 0x4c04
	int 0x21

exit_ok:
	mov ax, 0x4c00
	int 0x21

no_output:
	mov dx, offset no_output_message
	call print_string
	mov ax, 0x4c03
	int 0x21

copy_failed:
	mov dx, offset copy_error_message
	call print_string
	mov ax, 0x4c05
	int 0x21

memory_error:
	mov dx, offset memory_error_message
	call print_string
	mov ax, 0x4c06
	int 0x21

set_disc_paths:
	mov al, byte ptr [drive_index]
	add al, 'A'
	mov byte ptr [marker_path], al
	mov byte ptr [host_source], al
	mov byte ptr [menu_source], al
	mov byte ptr [nq_source], al
	mov byte ptr [q486_source], al
	mov byte ptr [quake_source], al
	ret

scan_output_drives:
	mov byte ptr [output_index], 0
scan_output:
	mov bl, byte ptr [output_index]
	inc bl
	mov ax, 0x4408
	int 0x21
	jc next_output
	cmp ax, 1
	jne next_output
	mov bl, byte ptr [output_index]
	inc bl
	mov ax, 0x4409
	int 0x21
	jc next_output
	test dx, 0x1000
	jnz next_output
	mov al, byte ptr [output_index]
	add al, 'A'
	mov byte ptr [output_root], al
	mov byte ptr [probe_path], al
	mov dx, offset output_root
	mov ah, 0x39
	int 0x21

	mov word ptr [probe_counter], 0
probe_again:
	call format_probe_name
	mov dx, offset probe_path
	mov cx, 0
	mov ax, 0x5b00
	int 0x21
	jnc probe_created
	cmp ax, 80
	jne next_output
	inc word ptr [probe_counter]
	cmp word ptr [probe_counter], 1000
	jb probe_again
	jmp next_output
probe_created:
	mov bx, ax
	mov ah, 0x3e
	int 0x21
	mov dx, offset probe_path
	mov ah, 0x41
	int 0x21
	call write_disc_hint
	jc next_output
	clc
	ret

next_output:
	inc byte ptr [output_index]
	cmp byte ptr [output_index], 26
	jb scan_output
	stc
	ret

format_probe_name:
	mov ax, word ptr [probe_counter]
	mov di, offset probe_path + 14
	mov cx, 4
format_hex:
	mov dx, ax
	and dx, 0x000f
	cmp dl, 9
	jbe hex_digit
	add dl, 'A' - 10
	jmp short store_digit
hex_digit:
	add dl, '0'
store_digit:
	mov byte ptr [di], dl
	dec di
	shr ax, 4
	loop format_hex
	ret

write_disc_hint:
	mov al, byte ptr [output_index]
	add al, 'A'
	mov byte ptr [disc_hint_path], al
	mov al, byte ptr [drive_index]
	add al, 'A'
	mov byte ptr [disc_hint_text], al
	mov dx, offset disc_hint_path
	xor cx, cx
	mov ah, 0x3c
	int 0x21
	jc disc_hint_failed
	mov word ptr [hint_handle], ax
	mov bx, ax
	mov dx, offset disc_hint_text
	mov cx, 1
	mov ah, 0x40
	int 0x21
	jc disc_hint_close_failed
	cmp ax, 1
	jne disc_hint_close_failed
	mov bx, word ptr [hint_handle]
	mov ah, 0x3e
	int 0x21
	clc
	ret
disc_hint_close_failed:
	mov bx, word ptr [hint_handle]
	mov ah, 0x3e
	int 0x21
disc_hint_failed:
	stc
	ret

copy_runtime_files:
	mov al, byte ptr [output_index]
	add al, 'A'
	mov byte ptr [host_dest], al
	mov byte ptr [menu_path], al
	mov byte ptr [nq_dest], al
	mov byte ptr [q486_dest], al
	mov byte ptr [quake_dest], al
	mov si, offset host_source
	mov di, offset host_dest
	call copy_one_file
	jc copy_runtime_failed
	mov si, offset menu_source
	mov di, offset menu_path
	call copy_one_file
	jc copy_runtime_failed
	mov si, offset nq_source
	mov di, offset nq_dest
	call copy_one_file
	jc copy_runtime_failed
	mov si, offset q486_source
	mov di, offset q486_dest
	call copy_one_file
	jc copy_runtime_failed
	mov si, offset quake_source
	mov di, offset quake_dest
	call copy_one_file
	jc copy_runtime_failed
	clc
	ret

copy_runtime_failed:
	stc
	ret

/* Copy DS:SI to DS:DI using DOS handles and a small conventional buffer. */
copy_one_file:
	mov word ptr [source_path_pointer], si
	mov word ptr [dest_path_pointer], di
	mov dx, si
	mov ax, 0x3d00
	int 0x21
	jc copy_one_failed
	mov word ptr [source_handle], ax
	mov dx, word ptr [dest_path_pointer]
	mov cx, 0
	mov ah, 0x3c
	int 0x21
	jc copy_close_source_error
	mov word ptr [dest_handle], ax
copy_file_loop:
	mov bx, word ptr [source_handle]
	mov cx, 4096
	mov dx, offset copy_buffer
	mov ah, 0x3f
	int 0x21
	jc copy_close_both_error
	test ax, ax
	jz copy_file_done
	mov word ptr [bytes_read], ax
	mov bx, word ptr [dest_handle]
	mov cx, word ptr [bytes_read]
	mov dx, offset copy_buffer
	mov ah, 0x40
	int 0x21
	jc copy_close_both_error
	cmp ax, word ptr [bytes_read]
	jne copy_close_both_error
	jmp copy_file_loop
copy_file_done:
	mov bx, word ptr [dest_handle]
	mov ah, 0x3e
	int 0x21
	mov bx, word ptr [source_handle]
	mov ah, 0x3e
	int 0x21
	clc
	ret
copy_close_both_error:
	mov bx, word ptr [dest_handle]
	mov ah, 0x3e
	int 0x21
copy_close_source_error:
	mov bx, word ptr [source_handle]
	mov ah, 0x3e
	int 0x21
copy_one_failed:
	stc
	ret

print_string:
	mov ah, 0x09
	int 0x21
	ret

no_disc_message:
	.ascii "NitroQuake disc not found. Start this launcher from its CD.\r\n$"
no_output_message:
	.ascii "No writable local fixed disk found.\r\n$"
copy_error_message:
	.ascii "Could not stage the DOS launcher files on writable storage.\r\n$"
menu_error_message:
	.ascii "Could not start the DOS command interpreter or NQMENU.EXE.\r\n$"
memory_error_message:
	.ascii "Could not release enough DOS memory for the menu.\r\n$"

marker_path:
	/* The leading ?: drive slots are replaced before any path is opened. */
	.ascii "?:\\NQ\\NQ.ID\0"
host_source:
	.ascii "?:\\NQ\\CWSDPMI.DAT\0"
host_dest:
	.ascii "?:\\NQDATA\\CWSDPMI.EXE\0"
menu_source:
	.ascii "?:\\NQ\\NQMENU.EXE\0"
menu_path:
	.ascii "?:\\NQDATA\\NQMENU.EXE\0"
nq_source:
	.ascii "?:\\NQ\\NQ.EXE\0"
nq_dest:
	.ascii "?:\\NQDATA\\NQ.EXE\0"
q486_source:
	.ascii "?:\\NQ\\Q486.EXE\0"
q486_dest:
	.ascii "?:\\NQDATA\\Q486.EXE\0"
quake_source:
	.ascii "?:\\NQ\\QUAKE.EXE\0"
quake_dest:
	.ascii "?:\\NQDATA\\QUAKE.EXE\0"
output_root:
	.ascii "?:\\NQDATA\0"
output_cwd:
	.ascii "\\NQDATA\0"
probe_path:
	.ascii "?:\\NQDATA\\W0000.TMP\0"
disc_hint_path:
	.ascii "?:\\NQDATA\\DISC.TXT\0"
disc_hint_text:
	.ascii "?"
drive_index:
	.byte 0
output_index:
	.byte 0
probe_counter:
	.word 0
source_handle:
	.word 0
dest_handle:
	.word 0
bytes_read:
	.word 0
hint_handle:
	.word 0
source_path_pointer:
	.word 0
dest_path_pointer:
	.word 0
exec_params:
	.word 0
	.word 0x0080
	.word 0
	.word 0
	.word 0
	.word 0
	.word 0
blank_fcb:
	.space 37
copy_buffer:
	.space 4096
stack_space:
	.space 1024
stack_top:
program_end:
