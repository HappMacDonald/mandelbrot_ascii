#!/bin/perl -CS

##### Current Status
# `mandelbrot_point` will be an assembly language IPC pipe that will concentrate mandelbrot calculations for me.
# Step 1: This file, `mandelbrot_point_stub.pl` will be a prototype to mold the test harness around.
# Step 2: uh .. test harness. I guess I'll do as little as possible but strip things from this copy of mandelbrot_ascii.pl
#         prior to beginning TDD.
# Step 3: Assembly version. I would like to hit the ground running with SSE4.2 optimization. Scalars can eat me, bitches.
# Step 4: M̶u̶l̶t̶i̶t̶h̶r̶e̶a̶d̶ t̶h̶e̶ a̶s̶s̶e̶m̶b̶l̶y̶ v̶e̶r̶s̶i̶o̶n
#         Scratch that, I'll allow caller to handle multithreading. :P Just spin up one copy of `point` per core.
# Step 5: Build a perl wrapper that can lean on the power of mandelbrot_point.elf to both both quickly interactively explore,
#         and to output high resolution images or image series's to turn into video or uh .. I'unno man. T-shirts prolly.
#
##### API
# `mandelbrot_point` — be it the perl prototype or one of the assembly finished products — will speak on STDIN/STDOUT/STDERR
# "Caller" will spin up a copy such as via IPC::Run and interact interactively (lol) with those filehandles 
# We write in "job" orders in packed binary into STDIN
# ( prolly little endian because x86 is dumb but at least
#   perl (un)pack can speak that stupid horseshit as assembly would be more hard
#   pressed to decode it. Luckily that step is not part of a tight loop.
# ),
# and then read back out the results as packed binary as well.
#---------
# Wrapper will feed in jobs with this format:
# (mutually agreed job description size of 320 bits = 40 bytes)
# // all input and output across this socket will be LITTLE ENDIAN fttb.
# // maybe down the road I'll flip that byte order, but both PERL AND ASM
# // are simultaneously conspiring to make Big Endian more difficult to support.
# float64 "d" Xstart
# float64 "d" Ystart
# float64 "d" Xcurrent (same as Xstart Ystart for jobs that are just .. uh .. starting)
# float64 "d" Ycurrent (may be different to continue a partial calculation)
# uint32 "V" alreadyDoneIterarions (0 for beginning calculations)
# uint32 "V" MaximumIterations
# // Job will be done starting from `alreadyDoneIterarions`+1st iteration,
# // until either the point leaves abs(x,y)>=2.0 OR until MaximumIterations
# // is reached. No plans for flexibility on the escape radius just yet.
# ALSO: the special code of 320 bits set aka 40 x 0xFF bytes means "flush".
# `mandelbrot_point` will probably buffer requests into a cacheline of memory,
# before it slurps them in for processing. Blocking until either
# it judges that its seen enough input, or it sees a flush.
# so "flush" clarifies that caller isn't expecting
# to feed more data in any time soon.
#---------
# `mandelbrot_point` will process these jobs whenever the hell it feels like it.
# Out of order, who knows. Then it will output results in this format.
# (mutually agreed job description size of 320 bits = 40 bytes)
# (Fun fact: for the time being this happens to perfectly match the input format! :D)
# float64 "d" Xstart (exactly the same as input)
# float64 "d" Ystart (, so this value pair can be thought of as a job identifier as well)
# // Wherever the point got to. Can be used for handling the job in pieces if perl wants to,
# // or for handling different coloration depending on where things landed, or whatevs 
# float64 "d" Xcurrent 
# float64 "d" Ycurrent 
# uint32 "V" alreadyDoneIterarions (The only reason this would be < MaximumIterations is escape)
# uint32 "V" MaximumIterations (exactly the same as input, helps different jobs run to different breakpoints)
#---------
# In fact while I'm on that subject, the above is a brilliant test-case to include.
# I should pore over the above API for "undesirable states"
# to try to make "unrepresentable", even if only in the tests! :)
# I should also encourage the stub.pl version to simulate buffering,
# and zany out-of-order results just to keep TDD and prototype callers on their toes.
# where the rubber meets the road, current plan is 2 jobs per batch, as
# that would represent just the amount needed to fill an aligned 64-byte cache line.
# If we ever step up to AVX-512 we might fill 2 cache lines at a time instead and
# thus be able to handle 4x double jobs, or 2x quad jobs.
#---------
# Test ideas in English and/or pseudocode:
# * Survivable exception will be noted with an output that has XYstart,
#   and all zeros after that.
#   Caller can unambiguously test this with "is MaximumIterations==0?"
# * input:MaximumIterations==0 should throw an exception
#   eg the other non-index fields like XYcurrent also get zeroed in output.
# * For the lazy, STDERR will also have content in it in this situation.
# * Caller must feed in uint32 values, but these values' high bits must be clear,
#   for the goal of maintaining perfect congruence to non-negative signed 32 bit integers.
#   Otherwise input is invalid, and we must receive an exception.
# * When we pair valid inputs and outputs by XYstart, MaximumIterations must also match.
# * When abs(XYcurrent)>=2.001, no work should be done aka output should exactly match input.
# * Fuzz: Valid combinations of input should never (VCoISN) throw an exception.
# * Fuzz: VCoISN output:alreadyDoneIterarions > output:MaximumIterations
# * Fuzz: VCoISN output:alreadyDoneIterarions < input:alreadyDoneIterarions
# * A SINGLE, valid, trivial (eg abs(XYcurrent)>=2.00) job added to an empty queue
#   followed by stalling the input should stall for at least MIN_TIMEOUT_DURATION.
#   This helps to encourage batching of jobs
# * The same should be tested (one by one) with a small selection of known-fast inputs.
#   Known-fast means known to be calculable (either run out of maximumiterations
#   and/or escape) in well under MIN_TIMEOUT_DURATION.
# * A single trivial or near-trivial valid input immediately followed by a flush
#   SHOULD return faster than MIN_TIMEOUT_DURATION. (that's what flushing is for)
# * I should probably fuzz a selection of simple cases where test suite
#   independantly vets both input and output as well. :)

use strict;
use warnings;
# I cannot easily support "binary data" and UTF-8 at the same time.
# So, I'll force my own sense of text encoding to be 7-bit ASCII only,
# while binary segments of strings get to be 8-bit and not reliably
# iterpreted as string characters at all.
use bytes;

# use diagnostics -verbose;
use Data::Dumper;
use JSON;
use POSIX qw(floor mkfifo);
use constant
{ TRUE => 1
, FALSE => 0
, MAX_31_BIT_INTEGER => 0x7FFFFFFF
, ESCAPE_SQUARED => 4
, JOB_KEY_BYTE_SIZE => 16
, FLOAT64_BYTE_SIZE => 8
, PACK_JOB_BYTES => 40
, PACK_JOB_FORMAT => 'ddddVV'
, PACK_KEY_FORMAT => 'dd'
, XSTART_INDEX => 0
, YSTART_INDEX => 1
, XCURRENT_INDEX => 2
, YCURRENT_INDEX => 3
, CURRENT_ITERATION_INDEX => 4
, MAXIMUM_ITERATION_INDEX => 5
, FLUSH_CODE => pack('C*', @{[(255) x 40]})
};
use IO::Select;
use IO::Handle;
die unless STDIN->blocking(0); # Turn off input buffering
$|++; # Turn off output buffering
binmode(STDIN);
binmode(STDOUT);
binmode(STDERR);

my($input, $output);
my($INPUT_LENGTH_IN_BYTES) = my($OUTPUT_LENGTH_IN_BYTES) = 40;

my($select) = IO::Select->new();

$select->add(\*STDIN);

while($select->can_read())
{ my($softError) = FALSE;
  $! = 0;
  $@ = '';
  my($lengthRead) = sysread(STDIN, $input, $INPUT_LENGTH_IN_BYTES);
  exit if($lengthRead < 1);
  die("Only read $lengthRead bytes when $INPUT_LENGTH_IN_BYTES should have been pushed. $! $@")
    unless($lengthRead == $INPUT_LENGTH_IN_BYTES);
  die("Sysread says that we read $lengthRead bytes, but I'm only seeing ". length($input) ." bytes in the buffer. $! $@")
    unless(length($input) == $lengthRead);

  if($input eq FLUSH_CODE)
  { print FLUSH_CODE;
    next;
  }
  my($jobKey) = substr($input, 0, JOB_KEY_BYTE_SIZE); # this is Xstart and Ystart in packed form
#CORE::say STDERR $jobKey, encode_json(['input', unpack('H*', $input), [unpack(PACK_KEY_FORMAT, $input)], 'jobKey', unpack('H*', $jobKey), [unpack(PACK_KEY_FORMAT, $jobKey)]]);
  my($Xstart, $Ystart, $Xcurrent, $Ycurrent, $currentIterations, $maximumIterations)
  = unpack(PACK_JOB_FORMAT, $input);

  eval
  { myAssertSoft
      ( $jobKey
      , $currentIterations <= MAX_31_BIT_INTEGER
      , "CurrentIterations must have high bit unset"
      );

    myAssertSoft
      ( $jobKey
      , $maximumIterations <= MAX_31_BIT_INTEGER
      , "MaximumIterations must have high bit unset"
      );

    myAssertSoft
      ( $jobKey
      , $maximumIterations > 0
      , "MaximumIterations must be larger than zero"
      );

=pod
    myAssertSoft
      ( $jobKey
      , $maximumIterations >= $currentIterations
      , "MaximumIterations must be greater than or equal to CurrentIterations"
      );
=cut

  };
  # die($@);
  $softError = !!($@ =~ /Soft Assertion Failure/);

=pod
  until
  ( $softError
  ||$currentIterations>=$maximumIterations
  ||$Xcurrent*$Xcurrent + $Ycurrent*$Ycurrent > ESCAPE_SQUARED
  )
  { $currentIterations++;
    my $tempY = $Ycurrent*$Ycurrent;
    my $tempX = $Xcurrent*$Xcurrent - $tempY + $Xstart;
    $Ycurrent = 2 * $Xcurrent * $Ycurrent + $Ystart;
    $Xcurrent = $tempX;
  }
=cut

  output
  ( $softError
  , $Xstart, $Ystart
  , $Xcurrent, $Ycurrent
  , $currentIterations, $maximumIterations
  );
}

sub output
{ my $softError = shift;
  if($softError) # bad?
  { $_[2] = $_[3] = $_[4] = $_[5] = 0;
  }
  print pack(PACK_JOB_FORMAT, @_);
}

sub myAssertSoft
{ my($jobKey, $test, $message) = @_;
  if(!$test)
  { CORE::say STDERR $jobKey, $message;
    die('Soft Assertion Failure');
  }
}  

sub myAssertFatal
{ my($jobKey, $test, $message) = @_;
  if(!$test)
  { myAssertSoft($jobKey, FALSE, $message);
    exit 1;
  }
}  

# input: anonymous function and a hash reference
# A new hash reference with the same keys is created,
# every value of which is the output of the argument function
# when it is fed the corresponding value from the argument hashref.
sub hashMapValues
{ my($code) = shift;
  my($input) = shift;
  my(%output) = ();

  foreach my $key (keys %$input)
  { $output{$key} = $code->($input->{$key});
  }

  \%output;
}

# Floating point modulo, with gravity to negative infinity.
sub fmod
{ my($dividend) = $_[0]/$_[1];
  $_[1] * ($dividend - floor($dividend));
}

