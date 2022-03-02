# Current status:
# gcc -ggdb -Wall -F dwarf -nostartfiles -nostdlib -g3 -m64 mandelbrot_point.s libmb_s.s -o mandelbrot_point.elf64 && echo 'helloasdasd' | ./mandelbrot_point.elf64
# echo feeds data through stdin in one bucketfull
# this application writes back out the length of bucketfull on one line, followed by the actual data read on the next line.
# this seems to work as well, as long as you mind the rounding error on float64 '2.00..':
# perl -e 'print pack("ddddNN", 0,1,2,3,4,5);' | ./mandelbrot_point.elf64 | perl -MData::Dumper -e 'my $q=<>; chomp($q=<>); CORE::say length($q); CORE::say Dumper(unpack("ddddNN", $q));'

.include "libmb_s.h"

	.globl _start

# Definitions

JOBLENGTH = 40

.text
_start:
  leaq readWriteBuffer(%rip), %rdi # Store memory location into arg1
  mov $JOBLENGTH, %rsi # move length into arg2
  mov $STDIN, %rdx # define recently vacated arg3
  call getMemoryProcedure
  mov %rax, %rbx # Store successfully read byte count in a parent-owned register
  mov %rax, %rdi # copy read byte count into arg1
  leaq messageBuffer(%rip), %rax # pointer to ascii decimal result buffer
  call unsignedIntegerToStringBase10
  mov %rax, %rdi # move memory location from ret1 into arg1
  mov %rdx, %rsi # move length from ret2 into arg2
  mov $STDOUT, %rdx # define recently vacated arg3
  call putMemoryProcedure
  putNewlineMacro
  leaq readWriteBuffer(%rip), %rdi # move memory location into arg1
  mov %rbx, %rsi # move length from parent safe spot into arg2
  mov $STDOUT, %rdx # define recently vacated arg3
  call putMemoryProcedure
  putNewlineMacro
  systemExitMacro 69

# Data

  .data
readWriteBuffer:
  .skip 40
messageBuffer:
  .skip 20

