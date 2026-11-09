	.text
	.globl _CallClipWithAbi
_CallClipWithAbi:
	pushl %ebp
	pushl %ebx
	pushl %esi
	pushl %edi
	movl %esp,.Lclip_saved_stack
	movl 20(%esp),%eax
	pushl 28(%esp)
	pushl 28(%esp)
	movl $0x13572468,%ebp
	movl $0x24681357,%ebx
	movl $0x5aa55aa5,%esi
	movl $0xa55aa55a,%edi
	cld
	call *%eax
	addl $8,%esp
	xorl %eax,%eax
	cmpl .Lclip_saved_stack,%esp
	jne .Lclip_abi_bad
	cmpl $0x13572468,%ebp
	jne .Lclip_abi_bad
	cmpl $0x24681357,%ebx
	jne .Lclip_abi_bad
	cmpl $0x5aa55aa5,%esi
	jne .Lclip_abi_bad
	cmpl $0xa55aa55a,%edi
	jne .Lclip_abi_bad
	pushfl
	popl %edx
	testl $0x400,%edx
	jnz .Lclip_abi_bad
	jmp .Lclip_abi_return
.Lclip_abi_bad:
	movl $1,%eax
.Lclip_abi_return:
	cld
	movl .Lclip_saved_stack,%esp
	popl %edi
	popl %esi
	popl %ebx
	popl %ebp
	ret
	.bss
	.p2align 2
.Lclip_saved_stack:
	.space 4
