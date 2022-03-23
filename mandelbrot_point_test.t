#!/bin/perl -CS

#############################
##  Current protocol spec  ##
#############################
# 1. Caller invokes engine
# 2. Caller blocks, engine emits 31-bit integer specifying how many lanes to fill.
# 3. Caller will now prepare blocks of memory 40 x $lanes bytes long to pass
#    through pipes to make jobs happen..
# 4. I think we are safe to treat STDIN and STDOUT as buffers here:
#    caller can dump any number of COMPLETE jobs (no fragmentation allowed),
#    with any timing into STDIN then come back to check STDOUT at leasure
#    to pick up the results.
# 5. No flush codes: caller will fill all joblanes not being used for a particular
#    job batch with 0xFF bytes and will get the same in the result batches.
# 6. No timeouts: engine gets batches, processes batches, posts results
#    at full speed with no blocking until/unless the in pipe is empty.

use strict;
use warnings;
# I cannot easily support "binary data" and UTF-8 at the same time.
# So, I'll force my own sense of text encoding to be 7-bit ASCII only,
# while binary segments of strings get to be 8-bit and not reliably
# iterpreted as string characters at all.
use bytes;
# use feature 'unicode_strings';
use constant
{ FALSE => 0
, TRUE => 1
, PACK_JOB_BYTES => 48
# , PACK_JOB_FORMAT => 'ddddVV'
# , PACK_KEY_FORMAT => 'dd'
, PACK_PALLET_FORMAT => 'ddddddddVx4Vx4Vx4Vx4'
, PACKED_31BIT_INT => 'V'
, XSTART_INDEX => 0
, YSTART_INDEX => 1
, XCURRENT_INDEX => 2
, YCURRENT_INDEX => 3
, CURRENT_ITERATION_INDEX => 4
, MAXIMUM_ITERATION_INDEX => 5
# @{[(255) x 40]} mess here means array of 40 0xff's
# , FLUSH_CODE => pack('C*', @{[(255) x 40]})
, JOB_KEY_BYTE_SIZE => 16
, FLOAT64_BYTE_SIZE => 8
};
use Data::Dumper;
use JSON;
use Digest::CRC qw(crc64);
use List::Util qw(min max);
use POSIX qw(floor ceil round);
use Test::More;
# use Test::Trap;
use IO::Socket::UNIX;
use List::AllUtils qw(reduce);
use IPC::Run qw( start pump finish timeout );
use IO::Select;
use IO::Handle;
die unless STDIN->blocking(0); # Turn off input buffering
$|++; # Turn off output buffering
binmode(STDIN);
binmode(STDOUT);
binmode(STDERR);


my(@executableToTest) = qw(./mandelbrot_point_stub.pl);
# my(@executableToTest) = qw(./mandelbrot_point.elf64);
# my(@executableToTest) = qw(sed s/e/@/g);

my($childInput, $childOutput, $childError, $timer, $childProcess);
my($timeoutInterval) = 0.3;
my($ACCEPTABLE_LANE_CONFIGS) =
{ 1 => 1 # Scalar only? It might be good for testing or something, I'unno.
, 2 => 1 # SSE42
, 4 => 1 # AVX1/2
, 8 => 1 # AVX512
, 16 => 1 # AVX1024?
};
my($debug)=FALSE;

$childProcess = spawn();
my($ACTIVE_LANES) = getLanes();

die
( "Received this from engine instead of lanes data:"
. '('. unpack("H*", $childOutput) .')'
. " Child reported error:($childError)"
)
unless
( defined($ACTIVE_LANES)
&&!!$ACCEPTABLE_LANE_CONFIGS->{$ACTIVE_LANES}
);

$childOutput = $childError = '';

testPallet
( [ .1, 0
  , .1, 0
  , .1, 0
  , .1, 0
  , 0, 0
  , 1, 0
  ]
, [ .1, 0
  , .1, 0
  , .1, 0
  , .12, 0
  , 1, 0
  , 1, 0
  ]
, 'Value check #1'
);

# Not even using second value in this pallet because I'm too lazy to think of another test rn :P
testPallet
( [ .5, 0
  , .8, 0
  , 0, 0
  , 0, 0
  , 1000, 0
  , 1004, 0
  ]
, [ .5, 0
  , .8, 0
  , -2.0479, 0
  , 1.152, 0
  , 1003, 0
  , 1004, 0
  ]
, 'Value check #2'
);


done_testing();
exit 0; #Tests compleat.

sub testPallet
{ $childInput = pack(PACK_PALLET_FORMAT, @{shift()});
  my $expectedOutput = pack(PACK_PALLET_FORMAT, @{shift()});
  my $testName = shift;

  $childProcess->pump() while length $childInput;
  # die(Dumper($childInput, $childOutput, $childError));

  is(length($childOutput), 96, 'pallet size')
    or warn 'didn\'t get a proper sized pallet back';
  is(length($childError), 0, 'error check')
    or warn "Child reported the following error: $childError";

  ok(is_pallet($childOutput, $expectedOutput), $testName)
  ||( diag
      ( "Output mismatch!"
      . Dumper
        ( { childOutputElements => [unpack(PACK_PALLET_FORMAT, $childOutput)]
          , expectedOutputElements => [unpack(PACK_PALLET_FORMAT, $expectedOutput)]
          , childOutputHex => unpack('H*', $childOutput)
          , expectedOutputHex => unpack('H*', $expectedOutput)
          , childError => $childError
          }
        )
      )
    );

  $childInput = $childOutput = $childError = '';
}

=pod

# Soft Error test
feedChild
( [ 'MaximumIterations must have high bit unset'
  , [1, 1, 9, -3, 0.25, -1]
  , [1, 1, 0, 0, 0, 0]
  , 'MaximumIterations must have high bit unset'
  ]
);

# Soft Error test
feedChild
( [ 'CurrentIterations must have high bit unset'
  , [1, 2, -3, 0.25, -1, 9]
  , [1, 2, 0, 0, 0, 0]
  , 'CurrentIterations must have high bit unset'
  ]
);

# Soft Error test
feedChild
( [ 'MaximumIterations must be larger than zero'
  , [1, 2, -3, 0.25, 10, 0]
  , [1, 2, 0, 0, 0, 0]
  , 'MaximumIterations must be larger than zero'
  ]
);

# Value tests
die("Current status: I need to figure out how to test one value, and wait for a timeout w/o performing a flush. The 'feedchild()' structure seems to make assumptions which preclude that option, so I'll need to do some rethinking there.");

feedChild
( [ 'Value 1'
  , [-.1, -.9, 0, 0, 0, 1]
  , [-.1, -.9, -.1, -.9, 1, 1]
  ]
, [ 'Value 2'
  , [.1, -.1, 0, 0, 0, 2]
  , [.1, -.1, .1, -.12, 2, 2]
  ]
, [ 'Value 3'
  , [.25, .16, 0, 0, 0, 2]
  , [.25, .16, .2869, 0.24, 2, 2]
  ]
, [ 'Value 4'
  , [.68, .2, 0, 0, 0, 4]
  , [.68, .2, 1.67250176, 1.2406656, 3, 4]
  ]
, [ 'Value 5'
  , [-.1, -.8, 1.42, 1.42, 0, 1] # Should just barely have already escaped,
  , [-.1, -.8, 1.42, 1.42, 0, 1] # so no further iterations calculated.
  ]
);

# TODO:
# { local $TODO = 'I need to test if MaximumIterations is always equal from input to output';
#   is('', '!');
# }

done_testing();
exit 0; #Tests compleat.



# while(length($childOutput))
# { CORE::say Dumper(length($childOutput), $childOutput, unpack(PACK_JOB_FORMAT, $childOutput));
#   $childOutput = substr($childOutput, PACK_BYTES);
# }

# $childProcess->finish();
# $childProcess->kill_kill();

=cut

# Returns handle to child process
sub spawn
{ start
  ( \@executableToTest
  , '<', \$childInput
  , '>', \$childOutput
  , '2>', \$childError
  , ( $timer = timeout $timeoutInterval )
  );
}

# This learns how many lanes to prepare per job pallet
sub getLanes
{ $childInput = '';
  $childProcess->pump();
  unpack(PACKED_31BIT_INT, $childOutput);
}


sub is_pallet
{ my(@a) = unpack(PACK_PALLET_FORMAT, shift);
  my(@b) = unpack(PACK_PALLET_FORMAT, shift);
  my($tolerance) = shift || 1e-6;

  # Since all items are either int or float, we can treat them as
  # all as float safely for comparison's sake.

  my @c = grep { abs($a[$_]-$b[$_])>$tolerance } 0..$#a;
  !@c;
}

=pod
# 100% Unique string based upon Xstart and Ystart values
# to match up inputs with outputs.
# Same as substr($packedData, 0, <something>)..
# but this uses unpacked input.
sub distillKey
{ my $unpacked = shift;
  my $result
  = pack
    ( PACK_KEY_FORMAT
    , $unpacked->[XSTART_INDEX]
    , $unpacked->[YSTART_INDEX]
    );
# CORE::say STDERR
#   encode_json
#   ( [ 'Encoding', $unpacked
#     , $unpacked->[XSTART_INDEX], $unpacked->[YSTART_INDEX]
#     , $result, [unpack(PACK_KEY_FORMAT, $result)]
#     ]
#   );
  return $result;
}

# Same as above but it yoinks the first JOB_KEY_BYTE_SIZE bytes from a packed string instead.
# Returns key (first JOB_KEY_BYTE_SIZE bytes) and remainder of packed data in list context.
sub lopKey
{ my($Xstart, $Ystart, $remainder) = unpack(PACK_KEY_FORMAT .'a*', $_[0]);
  
  ( pack(PACK_KEY_FORMAT, $Xstart, $Ystart)
  , $remainder
  );
}
# sub lopKey
# { ( substr($_[0], 0, JOB_KEY_BYTE_SIZE) # First N bytes
#   , substr($_[0], JOB_KEY_BYTE_SIZE) # Everything after first N bytes
#   );
# }

# Accepts arrayref of arrayref job inputs,
# and another arrayref of arrayref job expected outputs.
# Optional third argument is "expected error on STDERR".
# Returns arrayref of arrayref of actual outputs.
sub feedChild
{ my $tests = {};
  my $numberOfJobs = scalar(@_);

  $childOutput = $childError = '';

  while(my $test = shift)
  { my $label = shift @$test;
    my $input = shift @$test;
    my $expectedOutput = shift @$test;
    my $expectedSTDERROutput = shift(@$test) || '';
    my $inputKey = distillKey($input);

    $tests->{$inputKey} =
    { label => $label
    , input => $input
    , expectedOutput => $expectedOutput
    , expectedSTDERROutput => $expectedSTDERROutput
    , error => '' # default in case nothing gets received later
    };
    
CORE::say encode_json(['input', $input, 'key', [unpack(PACK_KEY_FORMAT, $inputKey)], 'label', $label]);

    $childInput = pack(PACK_JOB_FORMAT, @$input);

# CORE::say encode_json(['input before single input', length $childInput, $childInput]);
# CORE::say encode_json(['output before single input', length $childOutput, $childOutput]);
print STDERR '[feedChild pump';
    $childProcess->pump() while length $childInput;
CORE::say STDERR ']';
# CORE::say encode_json(['input after single input', length $childInput, $childInput]);
CORE::say encode_json(['output after single input', length $childOutput, $childOutput]);
  }
# CORE::say encode_json(['input before flush', length $childInput, $childInput]);
# CORE::say encode_json(['output before flush', length $childOutput, $childOutput]);
  flush();
# CORE::say encode_json(['input after flush', length $childInput, $childInput]);
# die(Dumper($childOutput, length $childOutput)) if $debug;

  while(my $outputPacked = substr($childOutput, 0, PACK_JOB_BYTES) )
  { 
# die(encode_json(['uh.. wha?', $childOutput, $outputPacked, , !!$outputPacked]));
    $childOutput = substr($childOutput, PACK_JOB_BYTES);
    
    next if $outputPacked eq FLUSH_CODE;
    my $output = [unpack(PACK_JOB_FORMAT, $outputPacked)];
    my $outputKey = distillKey($output);
# CORE::say encode_json(['key', [unpack(PACK_KEY_FORMAT, $outputKey)], 'output', $output]);

    if(!defined $tests->{$outputKey})
    { die
      ( 'Test harness failure, got output'
      , encode_json($output)
      , encode_json([unpack("H*", $outputPacked)])
      , 'matching no input ever fed in.'
      , Dumper($tests)
      );
    }
    $tests->{$outputKey}{output} = $output;
  }
# die(encode_json(['Well, at least we didn\'t try to process that nonsense. 😝', Dumper($tests)]));

  while(length $childError)
  { # regex matches and lops off everything up until
    # end of string or next newline, whichever comes first.
    $childError =~ s/^(.*)(?:\n|$)//;
    my($errorKey, $error) = lopKey($1);
# CORE::say encode_json(['key', [unpack(PACK_KEY_FORMAT, $errorKey)], unpack('H*', $errorKey), 'error', $error]);
    
    if(!defined $tests->{$errorKey})
    { my($Xstart, $Ystart) = unpack(PACK_KEY_FORMAT, $errorKey);
      die
      ( 'Test harness failure, got error'
      , "($Xstart,$Ystart) ($error)"
      , 'matching no input ever fed in.'
      );
    }

    $tests->{$errorKey}{error} = $error||'';
  }

    # ... uh ... needs a rewrite: my $test = $tests->{$outputKey};

  foreach my $jobKey (keys %$tests)
  { my $test = $tests->{$jobKey};

CORE::say STDERR encode_json([$test->{error}, $test->{expectedSTDERROutput}, crc64($test->{error}), crc64($test->{expectedSTDERROutput})]);

    is
    ( $test->{error}
    , $test->{expectedSTDERROutput}
    , 'Error check for `'. $test->{label} .'`'
    );

    # Compare output with matching expected output.
    is_deeply
    ( $test->{output}
    , $test->{expectedOutput}
    , 'Value check for `'. $test->{label} .'`'
    ) || diag Dumper($test);
    
    if($test->{error} ne '') # Any reported error on STDERR..
    { is
      ( $test->{output}[MAXIMUM_ITERATION_INDEX]
      , 0
      , 'MaximumIteration panic check for `'. $test->{label} .'`'
      );
    }
    else # STDERR is clean
    { is
      ( $test->{output}[MAXIMUM_ITERATION_INDEX]
      , $test->{input}[MAXIMUM_ITERATION_INDEX]
      , 'MaximumIteration solidarity check for `'. $test->{label} .'`'
      );
    }
  }
}