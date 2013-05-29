#!/bin/env perl

use 5.010;      # Require at least Perl version 5.8
use strict;     # Must declare all variables before using them
use warnings;   # Emit helpful warnings
use Getopt::Long; # use GetOptions function to for CL args
use Storable qw/freeze thaw/;

my ($debug,$verbose,$help);

my $result = GetOptions(


);

if ($help) {
    help();
    exit(0);
}


my $code = "sub { return \"purple\"; }";
#my $code = "sub { my \$in = shift; return \$in; }";
#my $code = 'red';
#say $code;
#my $rtn;
#
#$rtn = eval $code;
#
#my $color = $@ ? $code : &$rtn('blue');
#say "color = '$color'";
#say "return of eval: $@";
#my $rtn = $code;

#say "\$rtn isa '", ref($rtn), "'";

#if (!$@) {
#
#    say &$rtn('blah');
#
#} else {
#    $rtn = $code;
#    say $rtn;
#}

my $color = _parse_option($code);

say $color;

say "OK";

sub help {

say <<HELP;


HELP

}

sub _parse_option {
    my $text = shift;

    my $rtn = eval $text;

    my $color = $@ ? $text : $rtn;

    return $color;
}
