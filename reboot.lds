ENTRY(_start)
SECTIONS
{
	. = 0x1C000000;
	.text : { *(.text) }
	.data : { *(.data) }
	.sdata : { *(.sdata) }
	.rodata : { *(.rodata)}

	. = 0x1C080000;

	bss_start = .;
	.bss : { *(.bss) }
	.sbss : { *(.sbss) }
	bss_end = .;
}
