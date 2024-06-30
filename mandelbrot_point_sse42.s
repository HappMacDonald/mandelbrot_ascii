# Current status:
# gcc -nostartfiles -nostdlib -O3 -Wall -g -gdwarf-4 -g3 -F dwarf -m64 mandelbrot_point.s -o mandelbrot_point.elf64 && ./mandelbrot_point_test.t
# This seems to work so far (just echos input, does not yet perform computation)
# Next step: SIMD Calculations at bench testing phase.
# Every single SIMD instruction appears to be functioning right when debugged,
# but the overall effect is still wrong: my port of the algorithm is flawed
# somehow.

.include "libmb_s.h"

	.globl _start

# Definitions

JOBLENGTH = 96 # perl pack syntax 'ddddddddx4Vx4Vx4Vx4V'
XMMBYTESIZE = 16
SIMD_Xstarts = %xmm0
SIMD_Ystarts = %xmm1
SIMD_Xcurrents = %xmm2
SIMD_Ycurrents = %xmm3
SIMD_CurrentIterations = %xmm6
SIMD_MaximumIterations = %xmm7
SIMD_onePerLaneUint63 = %xmm8
SIMD_EscapeSquared = %xmm10


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
  // mulpd SIMD_DoubleTwoDoubles, SIMD_Ycurrents
  addpd SIMD_Ycurrents, SIMD_Ycurrents
  mulpd SIMD_Xcurrents, SIMD_Ycurrents
  addpd SIMD_Ystarts, SIMD_Ycurrents

  // xmm11 (TempX) => SIMD_Xcurrents
  movaps %xmm11, SIMD_Xcurrents
//RELEASE xmm11 

  jmp calculateInnerLoop

// Reached by bail condition from above
calculateCleanup:
  movaps SIMD_Xcurrents, Xcurrents(%rip)
  movaps SIMD_Ycurrents, Ycurrents(%rip)
  movaps SIMD_CurrentIterations, CurrentIterations(%rip)

output:
  putMemoryMacro messageLocation=readWriteBuffer(%rip),length=$JOBLENGTH
  jmp input # loop back to begining to do it all again, baby!

goodEnd:
  mov $60, %rax # systemExit code
  mov $0, %rdi # return code to caller: no errors to report
  syscall

// badEnd:
//   mov $60, %rax # systemExit code
//   mov $1, %rdi # return code to caller: something done borked, brah!
//   syscall


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
EscapeSquared:
  .double 4.0,4.0 

