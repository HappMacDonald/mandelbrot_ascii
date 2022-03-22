# Current status:
# gcc -nostartfiles -nostdlib -O3 -Wall -g -gdwarf-4 -g3 -F dwarf -m64 mandelbrot_point.s -o mandelbrot_point.elf64 && ./mandelbrot_point_test.t
# This seems to work so far (just echos input, does not yet perform computation)
# Next step: SIMD Calculations at bench testing phase. Code compiles. 😲

.include "libmb_s.h"

	.globl _start

# Definitions

JOBLENGTH = 96 # perl pack syntax 'ddddddddxxxxVxxxxVxxxxVxxxxV'
XMMBYTESIZE = 16
SIMD_Xstarts = %xmm0
SIMD_Ystarts = %xmm1
SIMD_Xcurrents = %xmm2
SIMD_Ycurrents = %xmm3
SIMD_CurrentIterations = %xmm6
SIMD_MaximumIterations = %xmm7
SIMD_onePerLaneUint63 = %xmm8
SIMD_EscapeSquared = %xmm10
SIMD_DoubleTwoDoubles = %xmm11

// OFFSET_XSTARTS = 0
// OFFSET_YSTARTS = 16
// OFFSET_XCURRENTS = 32
// OFFSET_YCURRENTS = 48
// OFFSET_CURRENTITERATIONS = 64
// OFFSET_MAXIMUMITERATIONS = 72

# Macros


.text
_start:
  // On startup, report number of lanes that this engine supports.
  putMemoryMacro messageLocation=numberOfLanesToReport(%rip),length=$4

input:
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
calculatePrep:
  movaps Xstarts(%rip), SIMD_Xstarts
  movaps Ystarts(%rip), SIMD_Ystarts
  movaps Xcurrents(%rip), SIMD_Xcurrents
  movaps Ycurrents(%rip), SIMD_Ycurrents
  movaps CurrentIterations(%rip), SIMD_CurrentIterations
  movaps MaximumIterations(%rip), SIMD_MaximumIterations
  movaps onePerLaneUint63(%rip), SIMD_onePerLaneUint63
  movaps EscapeSquared(%rip), SIMD_EscapeSquared
  movaps DoubleTwoDoubles(%rip), SIMD_DoubleTwoDoubles

calculateInnerLoop:
  //xmm5 = Max>Cur
  movaps SIMD_MaximumIterations, %xmm5
  pcmpgtq SIMD_CurrentIterations, %xmm5

  //xmm4 = xmm11 = Xcurrent^2
  movaps SIMD_Xcurrents, %xmm4
  mulpd %xmm4, %xmm4
  movaps %xmm4, %xmm11

  //xmm9 = Ycurrent^2
  movaps SIMD_Ycurrents, %xmm9
  mulpd %xmm9, %xmm9

  //xmm9 +=> xmm4(CurrentMagnitudeSquared)
  addpd %xmm9, %xmm4
//xmm9 still Ycurrent squared
//xmm11 still Xcurrent squared

  //%xmm4 = %xmm4 < SIMD_EscapeSquared(EscapeSquared) / AT&T syntax comparison is backwards
  cmpltpd SIMD_EscapeSquared, %xmm4 

  //%xmm5(Bounded iterations?) &&=> %xmm4 (Bounded point? => ActiveCalculation)
  pand %xmm5, %xmm4
//RELEASE %xmm5

  //Abort if our mask is all zero
  ptest %xmm4, %xmm4
  jz calculateCleanup

  //Conditional CurrentIterations++
  //SIMD_onePerLaneUint63 &&=> xmm4 (mask => amount to increment)
  pand SIMD_onePerLaneUint63, %xmm4
  //xmm4 +=> SIMD_CurrentIterations
  paddq %xmm4, SIMD_CurrentIterations
//RELEASE %xmm4

  //The rest of the calculations are unconditional,
  //since at least one lane needs them done,
  //and since nobody cares about XYCurrent after CurrentIterations has
  //stopped increasing.

  //%xmm9 (Ysquared) subtracted from => %xmm11 (Xsquared => TempX)
  subpd %xmm9, %xmm11
//RELEASE xmm9

  //SIMD_Xstarts +=> %xmm11 (TempX)
  addpd SIMD_Xstarts, %xmm11

  //2 * SIMD_Xcurrents * SIMD_Xstarts *=> SIMD_Ycurrents (updated)
  mulpd SIMD_DoubleTwoDoubles, SIMD_Ycurrents
  mulpd SIMD_Xcurrents, SIMD_Ycurrents
  mulpd SIMD_Xstarts, SIMD_Ycurrents

  // xmm11 => SIMD_Xcurrents
  movaps %xmm11, SIMD_Xcurrents
//RELEASE xmm11 

  jmp calculateInnerLoop

// Reached by bail condition from above
calculateCleanup:
  // XYstarts ought to never change in calculateInnerLoop
  // movaps SIMD_Xstarts, Xstarts(%rip)
  // movaps SIMD_Ystarts, Ystarts(%rip)

  movaps SIMD_Xcurrents, Xcurrents(%rip)
  movaps SIMD_Ycurrents, Ycurrents(%rip)
  movaps SIMD_CurrentIterations, CurrentIterations(%rip)
  
  // MaximumIterations ought to never change in calculateInnerLoop
  // movaps SIMD_MaximumIterations, MaximumIterations(%rip)

  // All of the below are constants loaded into registers only for convenience.
  // movaps SIMD_onePerLaneUint63, onePerLaneUint63(%rip)
  // movaps SIMD_EscapeSquared, EscapeSquared(%rip)
  // movaps SIMD_DoubleTwoDoubles, DoubleTwoDoubles(%rip)



output:
  putMemoryMacro messageLocation=readWriteBuffer(%rip),length=$JOBLENGTH
  jmp input # loop back to begining to do it all again, baby!

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
Xstarts:
  .skip XMMBYTESIZE
Ystarts:
  .skip XMMBYTESIZE
Xcurrents:
  .skip XMMBYTESIZE
Ycurrents:
  .skip XMMBYTESIZE
CurrentIterations:
  .skip XMMBYTESIZE
MaximumIterations:
  .skip XMMBYTESIZE
onePerLaneUint63:
  .quad 1,1 
DoubleTwoDoubles:
  .double 2.0,2.0
EscapeSquared:
  .double 4.0,4.0 
// flushCode:
//   .fill 40,1,0xFF
// messageBuffer:
//   .skip 256

