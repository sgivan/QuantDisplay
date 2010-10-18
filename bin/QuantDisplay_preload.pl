#!/usr/bin/perl
#
#
#
use strict;
use warnings;
use Bio::DB::GFF;
use Getopt::Std;
use Data::Dumper;
#use BerkeleyDB;
use vars qw/ $opt_f $opt_h $opt_d $opt_v $opt_M $opt_o $opt_i $opt_p $opt_c $opt_r $opt_z /;

getopts('f:hdvMo:ipc:r:z:');

my ($file,$help,$debug,$verbose,$fuzzy) = ($opt_f,$opt_h,$opt_d,$opt_v,$opt_z);
my $scorecall = $opt_c || 6;
my $maxlength = 150;

# print "file = '$file'\n";
# print "help = '$help'\n";
# print "debug = '$debug'\n";

if ($help) {

my $script = $0;
$script =~ s/\/.+\///;

print <<HELP;

$script reads a GFF file and generates an output GFF file
that QuantDisplay_load.pl will use to populate
a gbrowse database

options

-h      print this help menu
-v      verbose output to terminal
-f      input GFF file name
-i      read from STDIN (this doesn't work yet)
-p      preserve all data from original file, otherwise truncates last column
-c      use the value in this column for QDcount
-r      when using -c, replace that column with this value (typically -r '.')
-o      output file name, otherwise use default name
-M      use this flag if RAM is limited -- much slower!


HELP
exit();
}

if (!$file && !$opt_i) {
    print "a name for an input file must be provided with -f option\nor use -i to read from STDIN";
    exit();
}

my (%db,%fcount) = ();

if ($opt_M) {
    no strict 'subs';
    print "tying hash to BerkeleyDB\n" if ($verbose);
    my $tmpdir = $ENV{TMPDIR} || "/tmp";
    my $dbfile = "$tmpdir/QDpreload";
    
    if ($@) {
        print "can't find BerkeleyDB, looking for DB_File\n" if ($verbose);
        eval {
            require DB_File;
            import DB_File;
        };
        if ($@) {
            print "can't find DB_File\n" if ($verbose);
            exit;
        } else {
            print "tying hash to a DB_File DB_HASH file '$dbfile'\n" if ($verbose);
            my $rtn = tie %db, 'DB_File',
                                        $dbfile,
    #                                   O_CREATE|O_RDWR,
    #                                   0644,
    #                                   $DB_File::DB_HASH;
        #                               -Mode           => '0644';
                                    ;
            if (!$rtn) {
                print "call to tie() failed: $!\n" if ($verbose);
                exit();
            }
        }
        
    } else {
    
        print "tying hash to a BerkeleyDB::Hash file '$dbfile'\n" if ($verbose);
        my $rtn = tie(%db, 'BerkeleyDB::Hash',
                                    -Filename => $dbfile,
                                    -Flags      => DB_CREATE|DB_TRUNCATE,
#                                   -Flags      => DB_CREATE,
                                    -Mode           => 0644,
                                );
        if (!$rtn) {
            print "call to tie() failed: $!\n" if ($verbose);
            exit();
        }
    }
    use strict 'subs';
}

if ($file) {
    open(IN,$file) or die "can't open '$file': $!";
} elsif ($opt_i) {
# copy STDIN
#
# this doesn't work because we rewind
# input file to generate output file
    open(IN,"<&STDIN") or die "can't copy STDIN: $!";
}

my $outfile = $opt_o;
if (!$outfile) {
    $outfile = $file;
    $outfile =~ s/\.gff//;
    $outfile .= "_QDpreload.gff";
}
open(OUT,">$outfile") or die "can't open QDpreload.gff: $!";

my $line_count;
#my ($refmol,$source,$type,$score,$phase,$group);
my ($refmol,$source,$type,%reftrack);
my @db = ();
while (<IN>) {
    ++$line_count;
    my $line = $_;
    chomp($line);
    my @values = split /\t/, $line;

#    if (!$reftrack{$values[0]} || eof) {# except, if eof returns 1, then the last value will not be processed
    if (!$reftrack{$values[0]}) {
        collapse() if ($fuzzy);
        write_to_file(\%db,$refmol,$source,$type);
        %db = ();
    }

    my ($start,$stop,$diff,$strand) = ($values[3],$values[4],$values[4]-$values[3],$values[6]);
    ($refmol,$source,$type) = ($values[0],$values[1],$values[2]);# if ($line_count == 1);
    my ($score,$phase,$group) = ($values[$scorecall-1],$values[7],$values[8]);
    ++$reftrack{$refmol};

    my $pk = "$values[0]$start$stop$strand";
    if ($opt_M) {
        $db{$pk} = $line;
    } else {
#       $db{$pk}[0] = $line;
    }

    if ($opt_M) {
        $fcount{$pk}++;
    } else {
        $db{$pk}{tally}++;
        if ($db{$pk}{tally} == 1) {
            $db{$pk}{coords} = [$start,$stop];
            $db{$pk}{data} = [$score,$phase,$group,$strand];
        }
    }

    last if ($debug && $line_count == 5);
    if ($verbose) {
        print "line count: $line_count\n" if ($line_count % 100000 == 0);
    }
} continue {
    if (eof) { # not sure why I need this here (isn't this section only visited when eof is true?), but otherwise doesn't work as expected
        collapse() if ($fuzzy);
        write_to_file(\%db,$refmol,$source,$type);
    }
}

#print "# of keys: ", scalar(keys %db), "\n" if ($verbose);
print "# of keys: ", scalar(keys %db), "\n";# if ($verbose);
#print "tallies collected\nfilling output file\n" if ($verbose);

#my %collapsed = ();
#if ($fuzzy) {
#    my %hofa = (); # hash of array references
#    #
#    # collapse data structure based on fuzzy start/stop coordinates
#    #
#    foreach my $key (keys %db) {
#        print "key: '$key'\tvalue: '$db{$key}'\n";
#        my @values = split /;/, $key;
#        print "@values\n\n";
#        $hofa{$values[0] . $values[3]}[$values[1]] = [$values[2], $db{$key}];
#    }
#    
#    foreach my $key (keys %hofa) {
#        print "refmol $key\n";
#        my $aref = $hofa{$key};
#        print "\$aref isa '", ref($aref), "'\n";
#        my $alength = scalar(@$aref);
#        print "\$alength = '$alength'\n";
#        for (my $i = $fuzzy; $i < $alength; ++$i) {
##
#            my $stop;
#            my $h = $i+$fuzzy;
##
#            if ($aref->[$i]) {
#                print "valid element at index $i\n";
#                print "start: $i\tstop: $hofa{$key}[$i][0] -- $hofa{$key}[$i][1]\n";
#                if (assigned(@$aref[$i..$h]) > 1) {
#                    print "will collapse multiple reads betw $i and $h\n";
#
#                    foreach my $scoord ($i+1..$h) {
#                        print "\$scoord: $scoord\n";
#                        if ($hofa{$key}[$scoord][0] && ($hofa{$key}[$scoord][0] - $hofa{$key}[$i][0] <= $fuzzy)) {
#                        
#                        }
#                    }
#                }
#                print "\n\n";
#            }
#        }
#    }
#}

print "finished\n\n" if ($verbose);

untie(%db) if ($opt_M);
close(IN) or warn("can't close 'IN': $!");
close(OUT) or warn("can't close 'OUT': $!");

sub assigned {
    my $sum = 0;
    my @a = @_;
    foreach my $element (@_) {
        next unless (defined($element) && $element->[0]);
        print "\$element = '$element' [",ref($element),"]\n";
        ++$sum;
    }
    print "returning '$sum' from sum()\n";
    return $sum;
}

sub collapse {
    my $db = shift;

    my %hofa = (); # hash of array references
    #
    # collapse data structure based on fuzzy start/stop coordinates
    #
    foreach my $key (keys %db) {
        print "key: '$key'\tvalue: '$db{$key}'\n";
        my @values = split /;/, $key;
        print "@values\n\n";
        $hofa{$values[0] . $values[3]}[$values[1]] = [$values[2], $db{$key}];
    }
    
    foreach my $key (keys %hofa) {
        print "refmol $key\n";
        my $aref = $hofa{$key};
        print "\$aref isa '", ref($aref), "'\n";
        my $alength = scalar(@$aref);
        print "\$alength = '$alength'\n";
        for (my $i = $fuzzy; $i < $alength; ++$i) {
#
            my $stop;
            my $h = $i+$fuzzy;
#
            if ($aref->[$i]) {
                print "valid element at index $i\n";
                print "start: $i\tstop: $hofa{$key}[$i][0] -- $hofa{$key}[$i][1]\n";
                if (assigned(@$aref[$i..$h]) > 1) {
                    print "will collapse multiple reads betw $i and $h\n";

                    foreach my $scoord ($i+1..$h) {
                        print "\$scoord: $scoord\n";
                        if ($hofa{$key}[$scoord][0] && ($hofa{$key}[$scoord][0] - $hofa{$key}[$i][0] <= $fuzzy)) {
                        
                        }
                    }
                }
                print "\n\n";
            }
        }
    }

}

sub write_to_file {
    my $db = shift;
    my($refmol,$source,$type) = @_;    
#    foreach my $key (sort { $db{$a}{coords}->[0] <=> $db{$b}{coords}->[0] } keys %db) {
    foreach my $key (sort { $db->{$a}{coords}->[0] <=> $db->{$b}{coords}->[0] } keys %$db) {
        
        $db->{$key}{data}->[2] =~ s/;.+;$/;/ unless ($opt_p);
        if (!$opt_c) {
            $db->{$key}{data}->[2] .= " QDcount $db->{$key}{tally}" . ";"; 
        } else {
            my $QDval = $db->{$key}{data}->[0];
            $db{$key}->{data}->[0] = $opt_r if ($opt_r);
            $db{$key}->{data}->[2] .= " QDcount " . sprintf("%.6f",$QDval) . ";" unless (!$QDval || $QDval eq '.' || $QDval == 0);
        }
        print OUT "$refmol\t$source\t$type\t" . $db->{$key}{coords}->[0] . "\t" . $db->{$key}{coords}->[1] . "\t" . $db->{$key}{data}->[0] . "\t" . $db->{$key}{data}->[3] . "\t" . $db->{$key}{data}->[1] . "\t" . $db->{$key}{data}->[2] . "\n";
    }
}
