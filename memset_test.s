.include "libmb_s.h"

	.globl _start

.text
_start:
  SSE42_InkStamp0xFF
  // leaq buffer(%rip), %rax
  //32=512/16
  SSE42_memset16ByteBlocks destinationAddress=buffer,repeat=32


.data
  .balign 16
prebuffer:
  .fill 512,1,0x69
buffer:
  .fill 1024,1,0xAA
postbuffer:
  .fill 512,1,0x69
