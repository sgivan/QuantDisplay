#!/usr/bin/env perl
#
#
#
use 5.8.8;# will probably work with lesser, but not tested
use strict;
use warnings;
use Bio::DB::GFF;
use Getopt::Std;
use Data::Dumper;
#use BerkeleyDB;
use vars qw/ $opt_f $opt_h $opt_d $opt_v $opt_M $opt_o $opt_i $opt_p $opt_c $opt_r $opt_z $opt_s /;

getopts('f:hdvMo:ipc:r:z:s');

my ($file,$help,$debug,$verbose,$fuzzy,$ignorestrand) = ($opt_f,$opt_h,$opt_d,$opt_v,$opt_z,$opt_s);
my $scorecall = $opt_c || 6;
my $maxlength = 150; # I don't think this is used anywhere else

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
-z      use fuzzy coordinate matching
        use like -z 2, which will collapse all reads within 2nt (start or stop coordinates)
-s      ignore strand of alignment
-o      output file name, otherwise use default name
-M      use this flag if RAM is limited -- much slower!
-d      debugging output


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

# The following loop creates a data structure of all the reads for
# a given reference molecule. When a new ref mol is encountered, 
# the data structure is passed to traverse() (if this is a fuzzy job)
# and write_to_file() to generate the output.
#
while (<IN>) {
    ++$line_count;
    my $line = $_;
    chomp($line);
    my @values = split /\t/, $line;

#    if (!$reftrack{$values[0]} || eof) {# except, if eof returns 1, then the last value will not be processed
    if (!$reftrack{$values[0]}) {
        traverse(\%db,$fuzzy) if ($fuzzy);
        write_to_file(\%db,$refmol,$source,$type);
        %db = ();
    }

    my ($start,$stop,$diff,$strand) = ($values[3],$values[4],$values[4]-$values[3],$values[6]);
    ($refmol,$source,$type) = ($values[0],$values[1],$values[2]);# if ($line_count == 1);
    my ($score,$phase,$group) = ($values[$scorecall-1],$values[7],$values[8]);
    ++$reftrack{$refmol};
    $strand = '+' if ($ignorestrand);

    my $pk = "$values[0]\0$start\0$stop\0$strand";
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
        traverse(\%db,$fuzzy) if ($fuzzy);
        write_to_file(\%db,$refmol,$source,$type);
    }
}

#print "# of keys: ", scalar(keys %db), "\n" if ($verbose);
print "# of keys: ", scalar(keys %db), "\n" if ($debug);
#print "tallies collected\nfilling output file\n" if ($verbose);

print "finished\n\n" if ($verbose);

untie(%db) if ($opt_M);
close(IN) or warn("can't close 'IN': $!");
close(OUT) or warn("can't close 'OUT': $!");

sub assigned {
    my $sum = 0;
    my @a = @_;
    foreach my $element (@_) {
        #next unless (defined($element) && $element->[0]);
        next unless (defined($element) && scalar(@$element));
        #print "\$element = '$element' [",ref($element),"]\n";
        print "adding to sum: '", scalar(@$element), "'\n" if ($debug);
        #++$sum;
        $sum += scalar(@$element);
    }
    print "returning '$sum' from sum()\n" if ($debug);
    return $sum;
}

#
# traverse() is where the fuzzy magic happens
#
sub traverse {
    my $db = shift;# this will be a reference to %db
    my $fuzzy = shift;

    #
    # %db has the following general structure:
    # $db{str}{tally} = integer
    # $db{str}{coords} = [start, stop]
    # $db{str}{data} = [score, phase, group, strand]
    #
    # where str is a unique string containing these values:
    # refmol\0start\0stop\0strand
    # this has gone through several changes, but currently this string
    # simply serves as a unique identifier for each feature
    #

    my %hofa = (); # hash of array references
    #
    # convert data structure to array of arrays
    #
    foreach my $key (keys %$db) {
        print "key: '$key'\tvalue: '$db->{$key}'\n" if ($debug);
        #my @values = split /;/, $key;
        my @values = split /\0/, $key;
        print "@values\n\n" if ($debug);
        #
        # build a hash of arrays of arrays keyed by refmol + strand.
        # however, this is unnecessary now because each refmol is independent
        #
        # first array contains start coordinates <-- this won't work if there are features of different lengths with same start coordinate
        # what if I use push to generate and array at each observed start coordinate?
        #

        push(@{$hofa{$values[3]}[$values[1]]}, [$values[2], $db->{$key}->{data}, $db->{$key}->{tally}, $values[1]]);
        # so, the data structure looks like this:
        # hofa{+}[695] = [ [], [], [] ]
        # at postion 695 on the pos strand, there are 3 features with the same start coordinate
        # each annonymous array looks like this:
        # [ stop coordinate, [ score, phase, group, strand ], tally, start coordinate ]
        #
    }

    print "traverse keys: '",  keys(%hofa), "'\n" if ($debug);

    foreach my $key (keys %hofa) {
        print "strand: $key\n" if ($debug);
        my $aref = $hofa{$key}; # $aref = either + array or - array of array references
        #print "\$aref isa '", ref($aref), "'\n";
        my $alength = scalar(@$aref);
        print "\$alength = '$alength'\n" if ($debug);

        #for (my $i = $fuzzy; $i < $alength; ++$i) { # why do I initialize $i to $fuzzy?
        #
        # $i will be the index of the array
        # the array is the length of the chromosome
        #
        for (my $i = 1; $i < $alength; ++$i) { 
            my $stop;
            my $h = $i+$fuzzy;# $h is the upper bound of the array slice to detect nearby reads

            if ($aref->[$i]) {
                print "at least one valid element at index $i\n" if ($debug);
                #foreach my $alist (@{$aref->[$i]}) {
                #    print "\$alist isa '", ref($alist), "'\n";
                #    print "start: $i\tstop: " . $alist->[0] . "\n";
                #}
                if (assigned(@$aref[$i..$h]) > 1) { # if there are multiple reads in array slice
                    print "try to collapse multiple reads with start coords betw $i and $h\n" if ($debug);

                    my ($laststop,@features) = (0);
                    #
                    # collect all feature anonymous arrayrefs
                    #
                    my @buffer = ();
                    foreach my $feature_list (@$aref[$i..$h]) {
                        # remember --
                        # each element of $feature list looks like this:
                        # [ stop coordinate, [ score, phase, group, strand ], tally, start coordinate ]
                        #
                        if (defined(@$feature_list)) {
                            #
                            # loop through features in this slice
                            # sort features by stop coordinate (we already know about start coordinate)
                            #
                            foreach my $ele (sort { $a->[0] <=> $b->[0] } @$feature_list) {
                                print "stop: '", $ele->[0], "'\n" if ($debug);
                                #$laststop = $ele->[0] unless ($laststop);
                                # if this is the first loop, push the read onto the array and move to the next
                                unless ($laststop) {
                                    $laststop = $ele->[0];
                                    push(@buffer,$ele);
                                    next;
                                }
                                print "laststop = $laststop\n" if ($debug);
                                #
                                # test for fuzziness at end coordinate
                                # ie, if this read's end coordinate falls outside of fuzzy value,
                                # it shouldn't be collapsed. It will be in the output, but it won't
                                # be collapsed. Remember that the reads have been sorted by end
                                # coordinate here. So, there may be a whole new set of reads that
                                # have end coordinates near a new one.
                                #
                                if ($ele->[0] - $laststop > $fuzzy) { # these reads should not be collapsed
                                    $laststop = $ele->[0];
                                    push(@buffer,$ele);
                                } else { # these reads should be collapsed
                                    # 
                                    # since we're collapsing, pop the last feature off of @buffer
                                    # and add to the tally
                                    # you keep the start coordinate of the anchor read 
                                    #
                                    my $tele = pop(@buffer);
                                    $tele->[2] += $ele->[2];
                                    push(@buffer,$tele);
                                    
                                    # construct hash key for anchor feature in %db
                                    #
                                    my $pkk = "$refmol\0$tele->[3]\0$tele->[0]\0$key";
                                    print "pkk: '$pkk'\n" if ($debug);

                                    # construct hash key of feature in %db that we are
                                    # collapsing into achor feature
                                    #
                                    my $pkt = "$refmol\0$ele->[3]\0$ele->[0]\0$key";
                                    #
                                    # add the tally value to the anchor feature 
                                    # and add to %db
                                    $db->{$pkk}{tally} += $db->{$pkt}{tally};
                                    # change stop coordinate of anchor feature to collapsing feature
                                    $db->{$pkk}{coords}->[1] = $ele->[0];

                                    print "collapsing '$pkt' [$db->{$pkt}]\n" if ($debug);
                                    #
                                    # and delete the original read from %db
                                    delete($db->{$pkt});
                                    print "now: ", $db->{$pkt}, "\n" if ($debug);
                                }
                            }
                        } # end of if (defined())
                    }

                    my $bcnt = 0;
                    if ($debug) {
                        foreach my $bele (@buffer) {
                            ++$bcnt;
                            print "buffer element $bcnt:\n\t", $bele->[0], ", ", $bele->[1], ", ", $bele->[2], "\n";
                        }
                    }

                    
                    $i = $h;
                } else { # still need to generate output if only 1 feature present at this coordinate
                    # actually, I don't need to do anything if no collapse is necessary
                    # these features will be printed without any further action here
                    #
                    #my %dbt = ();
                    #$dbt{unique} = {
                    #                    'tally'     =>  $aref->[$i][0][2],
                    #                    'coords'    =>  [$i,$aref->[$i][0][0]],
                    #                    'data'      =>  $aref->[$i][0][1],
                    #                };
                    #write_to_file(\%dbt,$refmol,$source,$type);

                }
                print "\n\n" if ($debug);
            } # end of if block
        } # end of for loop
    }

}
#
# write_to_file() will generate a GFF2-ish file
# will need to update this eventually to generate a GFF3 file
#
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
