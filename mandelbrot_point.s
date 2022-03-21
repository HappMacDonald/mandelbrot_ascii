# Current status:
# gcc -ggdb -Wall -F dwarf -nostartfiles -nostdlib -g3 -m64 mandelbrot_point.s libmb_s.s -o mandelbrot_point.elf64
# perl -e 'print pack("ddddVV", 0,1,2,3,4,5);' | ./mandelbrot_point.elf64 | perl -MJSON -e 'binmode(STDIN); my $q=<>; CORE::say length($q); CORE::say encode_json([$q, unpack("ddddVV", $q)]);'
# This seems to work so far (just echos input, does not yet perform computation)
# Also echos input when you swap in zero for CurrentIterations
# And if you swap in a zero for MaximumIterations, or a negative number for either "iterations" value,
# then it will properly *detect* a failed assertion and behave differently.
# It just won't behave *correctly* as far as I can tell.
# Seems to end w/ no STDOUT and no STDERR, and no coredump.
# So I've got to figure out how to best GDB that with challenging to set up STDIN.

.include "libmb_s.h"

	.globl _start

# Definitions

JOBLENGTH = 80 # perl pack syntax 'ddddddddVVVV'
XMMBYTESIZE = 16
// OFFSET_XSTART = 0
// OFFSET_YSTART = 8
// OFFSET_XCURRENT = 16
// OFFSET_YCURRENT = 24
// OFFSET_CURRENTITERATIONS = 32
// OFFSET_MAXIMUMITERATIONS = 36
// HIGH_32_BIT_MASK = 0x80000000


# Macros

/*
// Clobbers child-owned values
.macro softError message:req
  // Print the prefix for the error
  putMemoryMacro messageLocation=readWriteBuffer(%rip),length=$PREFIXLENGTH,fileDescriptor=$STDERR
  putMemoryMacro messageLocation=putsMessage\@(%rip),length=$putsMessage\@Length,fileDescriptor=$STDERR
	jmp softErrorEnd\@
putsMessage\@:
  .string "\message"
  putsMessage\@Length = . - putsMessage\@ - 1
  .align 8
softErrorEnd\@:

  putNewlineMacro fileDescriptor=$STDERR

  // Zero out final 32 bytes of job description
  xorps %xmm0, %xmm0 # Clear SSE4.2 128 bit register to write 16 bytes of zeros at a time
  leaq afterPrefix(%rip), %rax # load output buffer location
  movdqa      %xmm0, (%rax)
  addq $XMMBYTESIZE, %rax # increment to last chunk that needs zeroing
  movhps      %xmm0, (%rax)
  jmp _output
.endm
*/

.text
_start:
  // On startup, report number of lanes that this engine supports.
  putMemoryMacro messageLocation=numberOfLanesToReport(%rip),length=$4

  // Read first job pallet
  getMemoryMacro messageLocation=readWriteBuffer(%rip),length=$JOBLENGTH

checkInputLength:
  mov %rax, %rdi # Store successfully read byte count into potential exit value, if it doesn't turn out to match $JOBLENGTH.
  cmp $JOBLENGTH, %al # al is LSB of rax: did we read EXACTLY the number of bytes we wanted?
  jne goodEnd # If not, then bail back to shell or other caller.

// lookForFlushCode:
//   leaq readWriteBuffer(%rip), %rdi # Store memory location into arg1 again
//   leaq flushCode(%rip), %rsi # Store code to compare it against into arg2
//   mov $JOBLENGTH, %ecx # Store length of string to compare
//   cld # Clear direction flag, aka "crawl forwards through memory for this compare"
//   repe cmpsb # Compare strings in memory

//   # For now that just means skip the assertion checks.
//   # Later it will also mean skip the calculations for this input,
//   # and run all calculations for pending inputs, outputting them and then
//   # last of all outputting a flush code of our own.
//   jz _output # If strings are identical, treat this as a flush code.



/*
checkAssertions:
  leaq CurrentIterations(%rip), %rax # address where both Uint31 "iterations" values are stored, one after the other.
  movq (%rax), %rax # Load both Uint31 values into one 64-bit register
  rorq $32, %rax # swap MaximumIterations into LSDW
  testl $HIGH_32_BIT_MASK, %eax # Does LSDW have high bit set?
  jnz MaximumIterationsMustHaveHighBitUnset
  testl %eax, %eax # is LSDW currently zero?
  jz MaximumIterationsMustBeLargerThanZero
  rorq $32, %rax # swap CurrentIterations into LSDW
  testl $HIGH_32_BIT_MASK, %eax # Does LSDW have high bit set?
  jnz CurrentIterationsMustHaveHighBitUnset
*/

calculate:
// prep for inner loop, TBI
calculateInnerLoop:
// TBI

output:
  //// Write 40 bytes from readWriteBuffer into STDOUT
  putMemoryMacro messageLocation=readWriteBuffer(%rip),length=$JOBLENGTH
  // leaq readWriteBuffer(%rip), %rdi # move memory location into arg1
  // mov $JOBLENGTH, %rsi # move length into arg2
  // mov $STDOUT, %rdx # define recently vacated arg3
  // call putMemoryProcedure

  jmp _start # loop back to begining to do it all again, baby!

goodEnd:
  mov $60, %rax # systemExit code
  // mov $0, %rdi # return code to caller: no errors to report
  syscall

// badEnd:
//   mov $60, %rax # systemExit code
//   mov $1, %rdi # return code to caller: something done borked, brah!
//   syscall


  // This would convert the length of successfully read input into decimal, then print that to stdout.
  // mov %rax, %rdi # copy read byte count into arg1
  // leaq messageBuffer(%rip), %rax # pointer to ascii decimal result buffer
  // call unsignedIntegerToStringBase10
  // mov %rax, %rdi # move memory location from ret1 into arg1
  // mov %rdx, %rsi # move length from ret2 into arg2
  // mov $STDOUT, %rdx # define recently vacated arg3
  // call putMemoryProcedure
  // putNewlineMacro

  // This would print the contents of the read buffer to stdout.
  // leaq readWriteBuffer(%rip), %rdi # move memory location into arg1
  // mov %rbx, %rsi # move length from parent safe spot into arg2
  // mov $STDOUT, %rdx # define recently vacated arg3
  // call putMemoryProcedure
  // putNewlineMacro

/*
MaximumIterationsMustHaveHighBitUnset:
  softError message="MaximumIterations must have high bit unset"
  
MaximumIterationsMustBeLargerThanZero:
  softError message="MaximumIterations must be larger than zero"

CurrentIterationsMustHaveHighBitUnset:
  softError message="CurrentIterations must have high bit unset"
*/

# Data

  .data
numberOfLanesToReport:
  .quad 2
  .balign 64
readWriteBuffer:
  // .skip 40 // nvm, I'll break this out into fields below instead.
Xstart:
  .skip XMMBYTESIZE
Ystart:
  .skip XMMBYTESIZE
afterPrefix:
Xcurrent:
  .skip XMMBYTESIZE
Ycurrent:
  .skip XMMBYTESIZE
CurrentIterations:
  .skip 8
MaximumIterations:
  .skip 8
// flushCode:
//   .fill 40,1,0xFF
// messageBuffer:
//   .skip 256

