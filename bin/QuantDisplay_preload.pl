#!/usr/bin/perl
#
# $Id: QuantDisplay_preload.pl,v 3.2 2008/10/28 21:50:30 givans Exp $
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

# my $db = Bio::DB::GFF->new(
#                                                       -adaptor    =>  'memory',
#                                                       -gff            =>  $file,
#                                                   );
# 
# print "\$db isa '", ref($db), "'\n";

my (%db,%fcount) = ();

if ($opt_M) {
    no strict 'subs';
    print "tying hash to BerkeleyDB\n" if ($verbose);
    my $tmpdir = $ENV{TMPDIR} || "/tmp";
    my $dbfile = "$tmpdir/QDpreload";
    
#   eval {
#       require BerkeleyDB;
#       import BerkeleyDB;
#   };
    
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
while (<IN>) {
    ++$line_count;
    my $line = $_;
    my @values = split /\t/, $line;
    chomp($line);
    my ($start,$stop,$diff,$strand) = ($values[3],$values[4],$values[4]-$values[3],$values[6]);
#   print "start = $start, stop = $stop\n";
#   print "diff = $diff\n" if ($line_count == 1);
#   print "diff = $diff\n" if ($diff != 31);

#   my $pk = pack("a10I3",$values[0],$start,$stop, $strand eq '+' ? 1 : 2);
    my $pk = "$values[0];$start;$stop;$strand";
#
# 
    if ($opt_M) {
        $db{$pk} = $line;
    } else {
#       $db{$pk}[0] = $line;
    }

    #my @pk = unpack("A10I2",$pk);

#   my $pk = oct($values[0])|$start|$stop;
#   my @pk = $start&$stop;
#   @pk = unpack('C*',$values[0]);
#   my $pk = pack "C8", @pk;
#   if ($line_count <= 5) {
#       print "\$pk = '$pk', \@pk = '", join ':', @pk, "\n";
#   } else {
#       last;
#   }

#   if ($db{$pk}) {
#       print "duplicate coords: $start - $stop : $db{$pk}\n";
#   }
    if ($opt_M) {
        $fcount{$pk}++;
    } else {
#       $db{$pk}[1]++;
#       $db{$pk}[0]++;
        $db{$pk}++;
    }

    last if ($debug && $line_count == 5);
    if ($verbose) {
#       print "line count: $line_count\n" if ($line_count % 10000 == 0);
        print "line count: $line_count\n" if ($line_count % 100000 == 0);
    }
}

print "# of keys: ", scalar(keys %db), "\n" if ($verbose);
#sleep(10);
print "tallies collected\nfilling output file\n" if ($verbose);

my %collapsed = ();
if ($fuzzy) {
    my %hofa = (); # hash of array references
    #
    # collapse data structure based on fuzzy start/stop coordinates
    #
    foreach my $key (keys %db) {
        print "key: '$key'\tvalue: '$db{$key}'\n";
        my @values = split /;/, $key;
        print "@values\n\n";
#        $hofa{$values[0] . $values[3]}->[$values[1]][$values[2]] = $db{$key};
#        $hofa{$values[0] . $values[3]}[$values[1]][$values[2]] = $db{$key};
        $hofa{$values[0] . $values[3]}[$values[1]] = [$values[2], $db{$key}];
    }
    #print Dumper(%hofa);

#    if ($hofa{'chr1-'}->[1072][1113]) {
#        print "chr1-:1072-1113 = " . $hofa{'chr1-'}->[1072][1113] . "\n";
#    }
    
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

seek IN, 0, 0;
my %track = ();
while (<IN>) {
    my $line = $_;
    chomp($line);
    my @values = split /\t/, $line;
    chomp($line);
    my ($start,$stop,$diff,$strand) = ($values[3],$values[4],$values[4]-$values[3],$values[6]);
    my $pk = "$values[0];$start;$stop;$strand";

    unless ($track{$pk}) { # unless we've already seen a read like this before ...
        if ($db{$pk}) {
            $values[8] =~ s/;.+;$/;/ unless ($opt_p);
            if (!$opt_c) {
                $values[8] .= " QDcount $db{$pk}" . ";";
            } else {
                my $QDval = $values[$opt_c - 1];
                $values[$opt_c - 1] = $opt_r if ($opt_r);
#               $QDval =~ s/\.\d+//; # not sure why I need to do this
                $values[8] .= " QDcount " . sprintf("%.6f",$QDval) . ";" unless (!$QDval || $QDval eq '.' || $QDval == 0);
            }
#           print OUT "$line QDcount $db{$pk}\n";
#           print OUT join "\t", @values, " QDcount $db{$pk}\n";
            print OUT join "\t", @values, "\n";
        } else {
            print STDERR "Not found: $values[0] - $start - $stop - $strand\n";
        }
    }
    $track{$pk}++; # increment this so we don't duplicate the data at entry to unless {}
}


# foreach my $key (keys %db) {
#   #my ($refmol,$start,$stop) = unpack("A10I2",$key);
#   #$refmol =~ s/\0//g;
#   #print "$refmol\t$start\t$stop\t$db{$key}\n";
#   if ($opt_M) {
#       print OUT "$db{$key} QDcount $fcount{$key};\n";
#   } else {
# #     print OUT $db{$key}[0] . " QDcount " . $db{$key}[1] . ";\n";
# 
# #     my @ukey = unpack("a10I3",$key);
#       my @ukey = split /;/, $key;
# #     print OUT "'" . join ' ', @ukey . "'\t" . $db{$key}[0] . "\n";
# #     print OUT "'@ukey'\t" . $db{$key}[0] . "\n";
#       print OUT "'@ukey'\t" . $db{$key} . "\n";
#   }
# }

print "finished\n\n" if ($verbose);

untie(%db) if ($opt_M);
close(IN) or warn("can't close 'IN': $!");
close(OUT) or warn("can't close 'OUT': $!");

sub assigned {
#    print "sum() called\n";
#    print "number of arguments: ", scalar(@_), "\n";
#    print "@_\n";
    my $sum = 0;
    my @a = @_;
#    print "\@a isa '", ref(@a), "'\n";
    foreach my $element (@_) {
        next unless (defined($element) && $element->[0]);
        print "\$element = '$element' [",ref($element),"]\n";
        ++$sum;
    }
    print "returning '$sum' from sum()\n";
    return $sum;
}
