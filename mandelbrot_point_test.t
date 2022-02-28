#!/bin/perl -CS

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
, PACK_JOB_BYTES => 40
, PACK_JOB_FORMAT => 'ddddNN'
, PACK_KEY_FORMAT => 'dd'
, XSTART_INDEX => 0
, YSTART_INDEX => 1
, XCURRENT_INDEX => 2
, YCURRENT_INDEX => 3
, CURRENT_ITERATION_INDEX => 4
, MAXIMUM_ITERATION_INDEX => 5
# @{[(255) x 40]} mess here means array of 40 0xff's
, FLUSH_CODE => pack('C*', @{[(255) x 40]})
, JOB_KEY_BYTE_SIZE => 16
, FLOAT64_BYTE_SIZE => 8
};
use Data::Dumper;
use JSON;
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
# my(@executableToTest) = qw(sed s/e/@/g);

my($childInput, $childOutput, $childError, $timer, $childProcess);
my($timeoutInterval) = 0.3;
my($debug)=FALSE;

$childProcess = spawn();
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
feedChild
( [ 'Value 1'
  , [-.1, -.9, 0, 0, 0, 1]
  , [-.1, -.9, -.1, -.9, 1, 1]
  ]
, [ 'Value 2'
  , [-.1, -.9, -.1, -.9, 0, 1]
  , [-.1, -.9, -.9, -.72, 1, 1]
  ]
, [ 'Value 3'
  , [-.1, -.9, -.9, -.72, 0, 1]
  , [-.1, -.9, .1916, 0.396, 1, 1]
  ]
, [ 'Value 4'
  , [-.1, -.9, .1916, 0.396, 0, 1]
  , [-.1, -.9, -.22010544, -.7482528, 1, 1]
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

# This forces child to process all pending inputs
sub flush
{ $childInput = FLUSH_CODE;
  until(!!(substr($childOutput, -PACK_JOB_BYTES) eq FLUSH_CODE))
  { 
# die(encode_json({childOutput => $childOutput, childError => $childError, is => $childOutput =~ /FLUSH_CODE/}))
#   if(length($childOutput) + length($childError));
    eval { $childProcess->pump(); };
  }
}

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
    
# CORE::say encode_json(['key', [unpack(PACK_KEY_FORMAT, $inputKey)], 'label', $label, 'input', $input]);

    $childOutput = $childError = '';
    $childInput = pack(PACK_JOB_FORMAT, @$input);
  
    $childProcess->pump();
  }
  flush();

  while(my $outputPacked = substr($childOutput, 0, PACK_JOB_BYTES) )
  { $childOutput = substr($childOutput, PACK_JOB_BYTES);
    
    next if $outputPacked eq FLUSH_CODE;
    my $output = [unpack(PACK_JOB_FORMAT, $outputPacked)];
    my $outputKey = distillKey($output);
# CORE::say encode_json(['key', [unpack(PACK_KEY_FORMAT, $outputKey)], 'output', $output]);

    if(!defined $tests->{$outputKey})
    { die
      ( 'Test harness failure, got output'
      , encode_json($output)
      , 'matching no input ever fed in.'
      );
    }
    $tests->{$outputKey}{output} = $output;
  }

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
    );
    
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