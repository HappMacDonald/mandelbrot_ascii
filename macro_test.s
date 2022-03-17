.macro blargsnarf from=0, to=5
  .long   \from
  .if     \to-\from
  blargsnarf     "(\from+1)",\to
  .endif
.endm

	.globl _start

.data
_start:
  BLARGSNARF 0,5

