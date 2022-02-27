#!/bin/perl -CS

use strict;
use warnings;
use utf8;
use feature 'unicode_strings';
use constant
{ FALSE => 0
, TRUE => 1
, PACK_BYTES => 40
, PACK_FORMAT => 'ddddNN'
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

my(@executableToTest) = qw(./mandelbrot_point_stub.pl);
# my(@executableToTest) = qw(sed s/e/@/g);

my($childInput, $childOutput, $childError, $timer, $childProcess);
my($timeoutInterval) = 0.3;
my($debug)=FALSE;

# Soft Error test
$childProcess = spawn();
feedChild
( [ [1, 1, 9, -3, 0.25, -1] ]
, [ [1, 1, 0, 0, 0, 0] ]
, "MaximumIterations must have high bit unset\n"
);

# Soft Error test
$childProcess = spawn();
feedChild
( [ [1, 2, -3, 0.25, -1, 9] ]
, [ [1, 2, 0, 0, 0, 0] ]
, "CurrentIterations must have high bit unset\n"
);

# Soft Error test
$childProcess = spawn();
feedChild
( [ [1, 2, -3, 0.25, 10, 0] ]
, [ [1, 2, 0, 0, 0, 0] ]
, "MaximumIterations must be larger than zero\n"
);

TODO:
{ local $TODO = 'I need to test if MaximumIterations is always equal from input to output';
  is('', '!');
}

done_testing();
exit 0; #Tests compleat.



# while(length($childOutput))
# { CORE::say Dumper(length($childOutput), $childOutput, unpack(PACK_FORMAT, $childOutput));
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

# Accepts arrayref of arrayref job inputs,
# and another arrayref of arrayref job expected outputs.
# Optional third argument is "expected error on STDERR".
# Returns arrayref of arrayref of actual outputs.
sub feedChild
{ my $inputs = shift;
  my $numberOfInputs = scalar(@$inputs);
  my $expectedOutputs = shift;
  my $expectedSTDERROutput = shift() || '';
  my $returnValues;
  $childOutput = $childError = '';

  $childInput = reduce { return $a . pack(PACK_FORMAT, @$b); } '', @$inputs;
  until
  ( length($childOutput)==PACK_BYTES*$numberOfInputs
  ||length $childError
  )
  { $childProcess->pump()
  }
  is($childError, $expectedSTDERROutput);

  my $outputs = [];
  my($childOutputToSlice) = $childOutput;

  while(length($childOutputToSlice))
  { my $output =
      [ unpack
        ( PACK_FORMAT
        , substr($childOutputToSlice, 0, PACK_BYTES)
        )
      ];
    $childOutputToSlice = substr($childOutputToSlice, PACK_BYTES);

    # Compare output with matching expected output.
    # most notably $#{$output} means "current last index from @$output"
    push @$outputs, $output;
    is_deeply($output, $expectedOutputs->[$#{$outputs}]);
  }
}