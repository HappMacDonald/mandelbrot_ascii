#!/bin/perl -CS

##### Current Status
# CLI arguments:
# * [viewportCenterX default -0.5]
# * [viewportCenterY default 0]
# * [viewPortHeight default 8]
# * [maximumIterations default 1e2]
# So the following two calls are identical:
# ./mandelbrot_ascii.pl
# ./mandelbrot_ascii.pl -0.5 0 8 1e2
#
#############
# I wanna accept mouse input for moving about. Hehe!
# Here is a perl one-liner to experiment with reading mouse input:
# perl -e 'use IO::Select; use IO::Handle; die unless STDIN->blocking(0); $|++; sub end { print "\e[?1000l"; system("stty echo"); exit; } $SIG{INT} = \&end; system("stty -icanon; stty -echo"); my($select) = IO::Select->new(); $select->add(\*STDIN); print "\e[?1003h\e[?1015h"; while($select->can_read()) { sysread(STDIN, my($buf), 32); my(@buf) = split //, $buf; foreach my $chr (@buf) { if(ord($chr)==4) { end(); } if(ord($chr)>31 && ord($chr<127)) { print $chr; } else { print "\\d", ord($chr); } } print " "; } end();'

# ANSI mouse tracking breakdown:
# CSI = Control Sequence Introducer = <ESC> [
#
# == To turn on tracking
# CSI ?1015h -- Sets the mode of input to decimal characters, the way we like it.
# CSI ?9h -- turns on mouse down tracking only. Does also get right mouse, wheel up and down, wheel click.
# CSI ?1000h -- all of the above + mouseup on code 35. right/left/wheel-middle have mouseups. wheelup wheeldown do not.
# CSI ?1003h -- all of the above + mouse movements code 67.
#
# You're also going to want to unbuffer both input and output.
# So far I have had luck with:
# `use IO::Select; use IO::Handle; die unless STDIN->blocking(0); $|++;`
# and run system commands `stty -icanon; stty -echo`
# and set up some kind of interrupt handler/cleanup for:
# `stty echo`, resetting color, turning off tracking, etc
# to keep user's prompt from going all fubar.
# 
# == To turn off any/all types of tracking mentioned above
# CSI ?1000l
#
# == To capture CTRL-C interrupt
# (I probably need to do more to protect shells in case of unknown interrupts as well)
# $SIG{INT} = \&yourCleanupSubroutine
# Must do that before changing the terminal, just because interrupts choose their own timing. :P
#
# == To read a batch of input including codes:
# my($select) = IO::Select->new(); $select->add(\*STDIN);
# while($select->can_read())
# { sysread(STDIN, my($buf), 32); # "32" buffer length simply chosen to be long enough to capture any entire codes
#   # process $buf. If any character in the buffer is EOF (ord(EOF) == 4) then you might wanna bail.
#   # Always remember to call your cleanup routine and exit there instead of quitting the whole app!
# }
# # Also call your cleanup function at the end of your app, for good measure.
#
# == Codes you'll sysread from mouse events
# below <something> means a decimal number. So "123" gets read as literally 1, 2, 3 characters in input.
# CSI<type of event>;<column=x>;<row=y>M
# Rows and columns count from 1 at the far upper left corner of the screen.
# The following codes reveal the following types of events,
# as long as you have asked to track that event type.
# 67 Mouse moved over/into this character position
# 32 Left mouse down
# 34 right mouse down
# 33 middle mouse down
# 35 AFAICT any mouse button up
# -- If user presses down on multiple buttons, you'll get a 35 code for each one they release too..
# -- .. but that doesn't tell us which button got released each time. Bleagh!
# 96 Wheel roll up one notch (no 35 codes from this one)
# 97 Wheel roll down one notch (no 35 codes from this one)



use strict;
use warnings;
# use diagnostics -verbose;
# use Curses;
use Data::Dumper;
use POSIX qw(floor);
use feature 'unicode_strings';
use utf8;
use constant { TRUE => 1, FALSE => 0 };
use IO::Select;
use IO::Handle;
use JSON;
die unless STDIN->blocking(0); # Turn off input buffering
$|++; # Turn off output buffering
binmode(STDIN);

my($pseudographicAlphebetA) = " ░▒▓█";
my($mandelbrotInteriorCharacterA) = "☰";
my($pseudographicAlphebetB) = "▀";
my($ANSIControlSequenceIntroducer) = "\e[";
my($TAB) = "\t";
my($parameters) = {};

# Routine to perform terminal cleanup before ending program,
# Especially in case of an interrupt!
sub end
{ mouseAllTrackingStop();
  resetColors();
  system("stty echo"); # Begin allow echoing input to the screen again
  CORE::say
  ( 'Last viewed arguments, suitable for replay:'
  , $TAB, $parameters->{viewPortCenterX}
  , $TAB, $parameters->{viewPortCenterY}
  , $TAB, $parameters->{viewPortHeight}
  , $TAB, $parameters->{maximumIterations}
  );
  exit;
}
$SIG{INT} = \&end; # Make sure Ctrl-C flows through cleanup

sub setParameters
{ my $newParameters = {@_};

  foreach my $key (keys %$newParameters)
  { delete $newParameters->{$key}
      unless defined $newParameters->{$key};
  }

  # my font is 12px wide 24px tall
  # But testing with aspectRatio = 2 still yielded
  # circles that were 5% too tall.
  # So final adjustment was eyeballed.
  $parameters =
  # { ( aspectRatio => $parameters->{aspectRatio} || 1.9
  #   , viewPortCenterX => $parameters->{viewPortCenterX} || -0.5
  #   , viewPortCenterY => $parameters->{viewPortCenterY} || 0
  #   , viewPortHeight => $parameters->{viewPortHeight} || 4
  #   , maximumIterations => $parameters->{maximumIterations} || 1e2
  { ( aspectRatio => 1.9
    , viewPortCenterX => -0.5
    , viewPortCenterY => 0
    , viewPortHeight => 4
    , maximumIterations => 1e2
    , %$parameters
    , %$newParameters
    )
  };

# die
# ( Dumper
#   ( \( %$parameters
#     , aspectRatio => 1.9
#     , viewPortCenterX => -0.5
#     , viewPortCenterY => 0
#     , viewPortHeight => 4
#     , maximumIterations => 1e2
#     , %$newParameters
#     )
#   )
# );

  $parameters->{viewPortCenter} =
    { x => $parameters->{viewPortCenterX}
    , y => $parameters->{viewPortCenterY}
    };
  $parameters->{viewPortSize} =
    { x => $parameters->{viewPortHeight}*$parameters->{aspectRatio}
    , y => $parameters->{viewPortHeight}
    };
  $parameters->{viewPortHalf} =
    hashMapValues
    ( sub { $_[0]/2 }
    , $parameters->{viewPortSize}
    );

  # my($parameters->{viewPortTextSize}) =
  # { x => 79#`tput cols`
  # , y => 23#`tput lines`-2
  # };
  $parameters->{viewPortTextSize} =
  { x => 0+`tput cols`
  , y => 0+`tput lines`
  };

# die(Dumper($parameters));
}
setParameters
( viewPortCenterX => $ARGV[0]
, viewPortCenterY => $ARGV[1]
, viewPortHeight => $ARGV[2]
, maximumIterations => $ARGV[3]
);

my($inputCommands) =
{ qr(^(?:\x{4}|\x{1B}$|q)) => 'QUIT'
, qr(^\+) => 'ZOOM IN'
, qr(^-) => 'ZOOM OUT'
, qr(^\]) => 'INCREASE MAXIMUM ITERATIONS'
, qr(^\[) => 'DECREASE MAXIMUM ITERATIONS'
, qr(^0) => 'RESET VIEW'
, qr(^\)) => 'DEFAULT VIEW'
, qr(^\Q${ANSIControlSequenceIntroducer}\EA) => 'UP'
, qr(^\Q${ANSIControlSequenceIntroducer}\EB) => 'DOWN'
, qr(^\Q${ANSIControlSequenceIntroducer}\EC) => 'RIGHT'
, qr(^\Q${ANSIControlSequenceIntroducer}\ED) => 'LEFT'
, qr(^\Q${ANSIControlSequenceIntroducer}\E(\d+);(\d+);(\d+)M) =>
    'MOUSE EVENT'
};

my $ANSI_RESPONSE_LEFT_BUTTON = 32;
my $ANSI_RESPONSE_RIGHT_BUTTON = 34;
my $ANSI_RESPONSE_SCROLL_UP = 96;
my $ANSI_RESPONSE_SCROLL_DOWN = 97;
my $ANSI_RESPONSE_MIDDLE_BUTTON = 33;


while(1)
{ drawSet();

  REPEAT_INPUT:
  my(@result) = acceptInput();
  if($result[0] eq 'QUIT') # Primary program exit
  { end() }
  elsif($result[0] eq 'ZOOM IN')
  { setParameters( viewPortHeight => $parameters->{viewPortHeight} / 2 ); }
  elsif($result[0] eq 'ZOOM OUT')
  { setParameters( viewPortHeight => $parameters->{viewPortHeight} * 2 ); }
  elsif($result[0] eq 'INCREASE MAXIMUM ITERATIONS')
  { setParameters
    ( maximumIterations => $parameters->{maximumIterations} * 4
    );
  }
  elsif($result[0] eq 'DECREASE MAXIMUM ITERATIONS')
  { setParameters
    ( maximumIterations => $parameters->{maximumIterations} / 4
    );
  }
  elsif($result[0] eq 'RESET VIEW') # Reset to command line params
  { # Clear out all old values first
    # so that defaults will override previous ephemera.
    $parameters = {};
    setParameters
    ( viewPortCenterX => $ARGV[0]
    , viewPortCenterY => $ARGV[1]
    , viewPortHeight => $ARGV[2]
    , maximumIterations => $ARGV[3]
    );
  }
  elsif($result[0] eq 'DEFAULT VIEW') # Reset to ultimate defaults
  { # Clear out all old values first
    # so that defaults will override previous ephemera.
    $parameters = {};
    setParameters();
  }
  elsif($result[0] eq 'UP')
  { setParameters
    ( viewPortCenterY =>
      ( $parameters->{viewPortCenterY}
      + $parameters->{viewPortSize}{y}/3
      )
    );
  }
  elsif($result[0] eq 'DOWN')
  { setParameters
    ( viewPortCenterY =>
      ( $parameters->{viewPortCenterY}
      - $parameters->{viewPortSize}{y}/3
      )
    );
  }
  elsif($result[0] eq 'LEFT')
  { setParameters
    ( viewPortCenterX =>
      ( $parameters->{viewPortCenterX}
      - $parameters->{viewPortSize}{x}/3
      )
    );
  }
  elsif($result[0] eq 'RIGHT')
  { setParameters
    ( viewPortCenterX =>
      ( $parameters->{viewPortCenterX}
      + $parameters->{viewPortSize}{x}/3
      )
    );
  }
  elsif($result[0] eq 'MOUSE EVENT')
  { my($zoom);
# CORE::say Dumper(\@result);
    if($result[1] == $ANSI_RESPONSE_LEFT_BUTTON)
    { $zoom = 2; } # zoom in 2x
    elsif($result[1] == $ANSI_RESPONSE_RIGHT_BUTTON)
    { $zoom = 1; } # No zoom, just recenter
    elsif($result[1] == $ANSI_RESPONSE_SCROLL_UP)
    { $zoom = 10; } # zoom in 10x
    elsif($result[1] == $ANSI_RESPONSE_SCROLL_DOWN)
    { $zoom = 0.2; } # zoom out 5x
    elsif($result[1] == $ANSI_RESPONSE_MIDDLE_BUTTON)
    { $zoom = 33; } # zoom in 33x
    setParameters
    ( viewPortCenterX =>
        cellToPlane('x', $result[2], TRUE)
    , viewPortCenterY =>
        cellToPlane
        ( 'y'
          # Mirror input vertically
        , $parameters->{viewPortTextSize}{y} - $result[3]
        , TRUE
        )
    , viewPortHeight => $parameters->{viewPortHeight} / $zoom
    );
  }
  else
  { print "Bad input, trying again..";
    goto REPEAT_INPUT;
  }
}



sub drawSet
{ resetScreen();
  my($startYindex) = $parameters->{viewPortTextSize}{y};
  my($topOfScreen) = TRUE;
  while($startYindex-- >0)
  { resetColors();
    print "\n" unless $topOfScreen;
    # sleep 2;
    $topOfScreen = FALSE;

    # Two samples per character
    my($startYs) =
    [ cellToPlane('y', $startYindex+0.25)
    , cellToPlane('y', $startYindex-0.25)
    ];
    my($startXindex) = $parameters->{viewPortTextSize}{x};
    while($startXindex-- > 0)
    { my($startX) =
        cellToPlane
        ( 'x'
        , $parameters->{viewPortTextSize}{x} - $startXindex + 1
        );
      my(@samples) = (0,0);
      
      foreach my $index (0..1)
      { my($startY) = $startYs->[$index];
        my($currentX, $currentY) = ($startX, $startY);
        my $iterations = 1; # 0 is reserved post-processing for "inside the M set"
        while
        ( $iterations < $parameters->{maximumIterations}
        &&$currentX*$currentX + $currentY*$currentY < 4
        )
        { $iterations++;
          my $tempY = $currentY*$currentY;
          my $tempX = $currentX*$currentX - $tempY + $startX;
          $currentY = 2 * $currentX * $currentY + $startY;
          $currentX = $tempX;
        }
        # This is a quick trick to make "maxint" results reset to zero,
        # without changing any other valid output values.
        $iterations %= $parameters->{maximumIterations};
        $samples[$index] = $iterations;

        # if($iterations>=$parameters->{maximumIterations})
        # { print $mandelbrotInteriorCharacterA;
        # }
        # else
        # { printCellA($iterations);
        # }
    # CORE::say("!$iterations!");
      }
      printCellB(@samples);
    }
  }

  resetColors();
  select()->flush();
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

## printCellA is the first version: 1 sample per character, 5 color grayscale.
## Caller used to print the mandelbrot special character directly.
# Input: A single float
# Side Effect: Output to terminal a single pseudographic from
#   $pseudographicAlphebetA corresponding to that value such that
#   as values get larger, the distance between color transitions widens
#   exponentially.
# No return output
# sub printCellA
# { my($cellValue) = shift;
#   my($paletteLength) = length($pseudographicAlphebetA);

#   if(abs($cellValue)<1e-6)
#   { $cellValue = 0;
#   }
#   else
#   { $cellValue = abs($cellValue)<1e-6?0:log($cellValue);
#     $cellValue = $cellValue - floor($cellValue);
#     $cellValue = floor($cellValue*$paletteLength);
#   }
#   print substr($pseudographicAlphebetA, $cellValue, 1);
# }

## printCellB is the second version: 24 bit color support at 2 samples (2 unique colors) per character.
## Caller no longer prints the mandelbrot special character directly.
# Input: A single float representing iterations of top sample, then another representing bottom.
# Side Effect: Output to terminal a "half-upper-block" character
#   aka $pseudographicAlphebetB backed by foreground and background
#   color setting codes.
# No return output
sub printCellB
{ my($cellValues) = [@_];
  my($inputSwatchesMapToANSICommandCode) = [38, 48];

  foreach my $swatchIndex (0..1)
  { my($redChannel, $greenChannel, $blueChannel) = (0,0,0);
    my($cellValue) = $cellValues->[$swatchIndex];

# CORE::say "\nRaw cellValue = $cellValue";
  
    if(abs($cellValue)>1e-6) # else keep default black color
    { #This converts the integer "0 < number of iterations < Max iter" value
      #into a float representing a hue from 0 to 1, with logarithmic falloff
      #(as input gets larger, hue spins more slowly)
      $cellValue =
        abs($cellValue)<1e-6
        ? 0
        # : log($cellValue+3)/log(3.33333);
        : ($cellValue+3) ** 0.2;

      $cellValue = $cellValue - floor($cellValue);

# CORE::say "Cooked cellValue = $cellValue";

      #This is scaled so that hue is 0..6, helps some of the math below.
      my $hueZeroToSix = $cellValue*6;
# CORE::say "hueZeroToSix = $hueZeroToSix";

      # Original algorithm took hue + value + saturation,
      # but we know inside this if statement that we'll only ever work with
      # a value and saturation that both equal 1.
      # Thus the normally precomputed "chroma" = 1 and "antichroma" = 0,
      # and those have both been simplified clean out of the below equations.
      # --
      # On a scale of 0 to 1, how far is this hue away from one of
      # the three primary hues? R/G/B all yield 0, C/M/Y all yield 1,
      # and every hue between yields the LINEAR interpolation.
      my $huePrimaryDeviation = 1-abs(fmod($hueZeroToSix, 2) - 1);
# CORE::say "huePrimaryDeviation = $huePrimaryDeviation";

      # All color channels initialized to zero
      # , so color channels not mentioned in each stanza
      # will remain zero.
      if($hueZeroToSix<1) # Full red, variable green
      { $redChannel = 1;
        $greenChannel = $huePrimaryDeviation;
      }
      elsif($hueZeroToSix<2) # variable red, full green
      { $redChannel = $huePrimaryDeviation;
        $greenChannel = 1;
      }
      elsif($hueZeroToSix<3) # full green, variable blue
      { $greenChannel = 1;
        $blueChannel = $huePrimaryDeviation;
      }
      elsif($hueZeroToSix<4) # variable green, full blue
      { $greenChannel = $huePrimaryDeviation;
        $blueChannel = 1;
      }
      elsif($hueZeroToSix<5) # full blue, variable red
      { $blueChannel = 1;
        $redChannel = $huePrimaryDeviation;
      }
      else # variable blue, full red
      { $blueChannel = $huePrimaryDeviation;
        $redChannel = 1;
      }
    }
    #else keep default black color
    #end if

    print
    ( $ANSIControlSequenceIntroducer, $inputSwatchesMapToANSICommandCode->[$swatchIndex]
    , ';2'
    , ';', floor(255*$redChannel)
    , ';', floor(255*$greenChannel)
    , ';', floor(255*$blueChannel)
    , 'm'
    );
  }
  print $pseudographicAlphebetB;
}

sub acceptInput
{ system("stty -icanon; stty -echo"); # suppress input to screen
  binmode(STDIN); # not only confirm binmode, but also flush input stream.
  my($select) = IO::Select->new();
  $select->add(\*STDIN);
  mouseClickTrackingStart();
  while($select->can_read())
  { sysread(STDIN, my($buf), 32);
    while(length($buf))
    { foreach my $pattern (keys %$inputCommands)
      { unless($buf =~ $pattern)
        { #print to_json({buf=>$buf, pattern=>$pattern});
          next;
        }
        my(@command) = $inputCommands->{$pattern};
        if($command[0] eq 'MOUSE EVENT')
        { push @command, $1, $2, $3;
        }
        return @command;
      }
      $buf = substr($buf, 1);
    }
  }
  mouseAllTrackingStop();
}

# input:
# * coordinate to act along: x or y (single character string)
# * cell coordinate to translate to 
sub cellToPlane
{ my($axis) = shift;
  my($cellCoordinate) = shift;
  my($debug) = shift;

  $parameters->{viewPortCenter}->{$axis}
  - $parameters->{viewPortHalf}->{$axis}
  + $cellCoordinate
  * ( $parameters->{viewPortSize}->{$axis
    } / $parameters->{viewPortTextSize}{$axis}
    )
  ;
}

# Floating point modulo, with gravity to negative infinity.
sub fmod
{ my($dividend) = $_[0]/$_[1];
  $_[1] * ($dividend - floor($dividend));
}

sub resetScreen() { print $ANSIControlSequenceIntroducer, '2J', $ANSIControlSequenceIntroducer, '0;0H'; }
sub resetColors() { print $ANSIControlSequenceIntroducer, '0m'; }
sub mouseClickTrackingStart() { print $ANSIControlSequenceIntroducer, '?9h', $ANSIControlSequenceIntroducer, '?1015h'; }
sub mouseAllTrackingStop() { print $ANSIControlSequenceIntroducer, '?1000l'; }
