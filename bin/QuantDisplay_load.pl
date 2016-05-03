#!/usr/bin/env perl
# $Id: QuantDisplay_load.pl,v 4.9 2009/06/09 19:41:28 givans Exp $ 
#
#     QuantDisplay_load -- generate feature bins for gbrowse
#     Copyright (C) 2007  Scott Givan
# 
#     This program is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 3 of the License, or
#     (at your option) any later version.
# 
#     This program is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
# 
#     You should have received a copy of the GNU General Public License
#     along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
use strict;
use Bio::DB::GFF;
use Getopt::Std;
use lib '/home/sgivan/lib/perl5';
use lib '/home/sgivan/projects/COGDB/lib';
use vars qw/ $opt_h $opt_f $opt_F $opt_d $opt_u $opt_p $opt_H $opt_b $opt_r $opt_l $opt_a $opt_A $opt_R $opt_v $opt_c $opt_o $opt_i $opt_n $opt_m $opt_M $opt_X $opt_w/;

getopts('hf:Fdu:p:H:b:r:R:laAvco:in:m:M:X:w');

my $user = $opt_u || 'yeast';
my $password = $opt_p || undef;
my $dbhost = $opt_H || 'pearson.science.oregonstate.local';
my $db = $opt_b || 'yeast_chr1';
my $help = $opt_h || undef;
my $debug = $opt_d || undef;
my $verbose = $opt_v || $debug || undef;
my $featuretype = $opt_f || 'blah';
my $urefmol = $opt_r || 'I';
my $usage = "QuantDisplay_load.pl -p ( -h -f -d -u -H -b -v )";
my $refclass = $opt_R || 'chromosome';
my $QDcount = $opt_c || undef;
my $outfile = $opt_o || 'out.gff';
my $indepenent = $opt_i || undef;
my $n_window = $opt_n || undef;
my $window_0 = $opt_m || 50;
#my $window_max = $opt_M || 50000;
my $window_max = $opt_M || 1000000;
#my $fast_algorithm = $opt_F || undef;
my $algorithm = $opt_X || 's';
my $smallwindows = $opt_w;

$| = 1;

if ($help) {

print <<HELP;

This script attempts to create bins in a gbrowse database
for user-specified feature types.  The resulting bins are
used by the QuantDisplay gbrowse plugin. The output file
from this script should be loaded into the primary gbrowse
database using bp_fast_load_gff.pl

$usage

ie: QuantDisplay_load.pl -u brachy_cluster -b brachy4-gbrowse-dev -p -H skynet.science.oregonstate.local -f perfect_match -R contig -a -c

Options

-h    print this help menu
-f    feature type (default = 'blah')
-l    list current feature types, then exit
-a    <feature type>
      perform analysis on all features of type <feature type>
      ie., contig, chromosome, assembly
-i    count each feature as independent
-c    for each feature, count based on QDcount attribute
-n    only use one window size (default = 50, minimum = 5)
-A    <feature type>
      list all features of type <feature type>, then exit
-m    minimum rolling window width
-M    maximum rolling window width
-R    reference molecule class (default = 'chromosome')
-r    reference molecule name (default = 'I')
-d    debugging mode
-v    verbose output to terminal
-u    user name for mysql database (default = 'yeast')
-p    use a password when connecting to MySQL database
-H    mysql hostname (default = pearson)
-b    mysql database name (default = 'yeast_chr1')
-o    output file name (default = out.gff)
-X    binning algorithm (s = default and slowest; f = fast; x = superfast)

HELP
exit();
}

if (!$password) {
  print STDERR "do you need to use a password [Y/n]? ";
  my $answer = <STDIN>;
  chomp($answer);
  if (!$answer || ($answer eq 'Y' or $answer eq 'y')) {
    print STDERR "password: ";
    $password = <STDIN>;
    chomp($password);
  } else {
#   exit();
  }
}

if ($debug) {
  print <<DEBUG;

user = '$user'
password = '$password'
dbhost = '$dbhost'
featuretype = '$featuretype'
urefmol = $urefmol
refclass = '$refclass'

DEBUG
# exit();
}


my $DB = Bio::DB::GFF->new(
  -adaptor  =>  'dbi::mysql',
  -dsn      =>  "dbi:mysql:" . $db . ";host=" . $dbhost . ";port=3306",
  -user     =>  $user,
  -pass     =>  $password,
);

my @types = $DB->types();

my $found = 0;
my %fmap;
foreach my $type (@types) {
  # asString returns method:source as string
  # look for method eq to $featuretype
  print "as String: " . $type->asString() . "\t";
  print "\ttype: " . $type->method() . " (use this as type argument)\n";
# $found = 1 if ($type->method() eq $featuretype);
  if ($type->method() eq $featuretype) {
    $found = 1;
    $fmap{$featuretype} = $type->asString();
  }
}
exit if ($opt_l);

if ($found) {
  print "\nfeature '$featuretype' found\n";
} else {
  print "\nfeature '$featuretype' not found\n";
  exit();
}

my @refmols = ();
#if ($opt_A || $opt_a) {
if (1) {
  print "finding all features of class '$refclass'\n" if ($opt_A);
  my @features = $DB->features($refclass);
  foreach my $feature (@features) {
    print "$refclass:  '", $feature->name(), "', length: ", $feature->length(), "\n" if ($opt_A);
    next if ((!$opt_A && !$opt_a) && $feature->name() ne $urefmol);
    push(@refmols,$feature->name());
  }
  exit() if ($opt_A);
}# else {
#    #push(@refmols,$urefmol);
#  push(@refmols,$DB->segment($urefmol));
#}

print "Everything is in place. Creating output file.\n" if ($verbose);

if ($debug) {
    print "refmols:\n";
    foreach my $name (@refmols) {
        print "\t'$name'\n";
    }
}

open (OUT,">$outfile") or die "can't open $outfile : $!";

# my @classes = $DB->classes();
# foreach my $class (@classes) {
#   print "class: $class\n";
# }

my @windows = ();
if ($n_window) {
  if ($n_window < 5) {
    print "minimum window size = 5\n" if ($verbose);
    exit();
  }
  push(@windows,$n_window);
} else {
# @windows = ($window_0,100,500,1000,5000,10000,25000,50000);
#  @windows = ($window_0, $window_0 * 2, $window_0 * 5, $window_0 * 10, $window_0 * 50, $window_0 * 100, $window_0 * 250, $window_0 * 500);
#  @windows = ($window_0, $window_0 * 2, $window_0 * 20, $window_0 * 100, $window_0 * 200, $window_0 * 500);
    if ($smallwindows) {
        @windows = ($window_0, $window_0 * 2, $window_0 * 5, $window_0 * 10, $window_0 * 50, $window_0 * 100, $window_0 * 500, $window_0 * 1000);
    } else {
        @windows = ($window_0, $window_0 * 2, $window_0 * 20, $window_0 * 100, $window_0 * 200, $window_0 * 500, $window_0 * 2000, $window_0 * 5000);
    }
}

my $refmol_count = 0;
my $reftime = time();
foreach my $refmol (@refmols) {
  if ($debug) {
    print "working with refmol: '$refmol' [$refmol_count]; \$refmol isa '", ref($refmol), "'\n";
    last if ($debug && ++$refmol_count > 1);
#    next;
  }
  my ($refmol_obj,@all_features,$all_features_count) = ();
  $refmol_obj = $DB->segment($refmol);# instantiating whole reference sequence (ie, chromosome, contig, assembly) object
#  if ($fast_algorithm) {
  if ($algorithm eq 'f') {
    print "fetching all features from database (", time(), ", ", time() - $reftime, ")\n" if ($debug);
    @all_features = sort { $a->start() <=> $b->start() } $refmol_obj->features($featuretype);# get all requested features for a refseq as sorted array
    print "sorting all features (", time(), ", ", time() - $reftime, ")\n" if ($debug);
    $all_features_count = scalar(@all_features);
    print "moving on (", time(), ", ", time() - $reftime, ")\n" if ($debug);
  } elsif ($algorithm eq 'x') {
  
    print "using superfast algorithm\n" if ($debug);
    my $arrayref = fast_fetch($refmol);
#    @all_features = sort { fstart($a) <=> fstart($b) } @$arrayref;
    @all_features = @$arrayref;
    $all_features_count = scalar(@all_features);
    
  }

  my $stop = $refmol_obj->length();
  my $array_index = 0;# used in fast algorithm
  #
  # this for loop is what marches down a reference molecule; ie, a chromosome or contig
  #
  for (my $i = 1; $i < $stop; $i += $window_0) { # window start coords should be every $window_0 nt
     if ($debug) {# set this to $debug to limit iterations during debugging
      if ($i >= (1000 * $window_0)) {
        print "exiting\n";
        print "elapsed time = ", time() - $reftime, "\n";
        exit();
      }
     }
    print "\n\n\nwindow start coord = $i\n" if ($debug);

      my ($last_stop,$running_count,$plus,$minus,$fcount) = ($window_0,0,0,0,0);
      my %features_counted = ();# use to avoid counting features more than once, see ~l253
#      my $array_index = 0;# used in fast algorithm
      my $inner_array_index = $array_index;

      foreach my $window (@windows) {# conceptually, windows will all have same start coord,  but different stop coords

        last if ($window > $window_max);
        if ( (($i-1)/$window) - int(($i-1)/$window) == 0) {# window discriminator (decides when a full-length window is intact)

          print "\tchecking in $window nt window\n" if ($debug);

          my %features = ();
          if (!$QDcount) { ## count each instance of feature
            print "\tcounting each feature as independent\n" if ($i == 1 && $verbose);
            %features = $DB->types(
                                    -ref      =>  $refmol,
                                    -class    =>  $refclass,
                                    -start    =>  $i,
                                    -stop     =>  $i - 1 + $window,
                                    -enumerate    =>  1,
                                  );
#             If -enumerate is true, then the function returns a hash (not a hash reference) in which the
#             keys are type names in "method:source" format and the values are the number of times each fea-
#             ture appears in the database or segment.

            print "\t$refmol subsegment  [", $i, ", ", $i - 1 + $window, "] has $features{$fmap{$featuretype}} features of type '$featuretype'\n" if (($debug || $verbose) && $features{$fmap{$featuretype}});
      
            printGFF($refmol,$featuretype,$i,$i - 1 + $window,$features{$fmap{$featuretype}},$window) if ($features{$fmap{$featuretype}});
  

          } else {
          ##
          ##
          ## count based on pre-computed QDcount attribute
          ##
          ##
            print "\tusing QDcount to determine feature count; refmol = '$refmol'\n" if ($i == 1 && $debug);
            my $feat_count = 0;
            my ($ss_start,$ss_stop) = (0,0);
            $ss_start = $window == $window_0 ? $i : $last_stop;# subsegment start
            $ss_stop = $i - 1 + $window;# subsegment stop
            $last_stop = $i + $window;
#            print "\$ss_start = $ss_start, \$ss_stop = $ss_stop, \$last_stop = $last_stop\n";
            

            if ($algorithm eq 'f') {
            ##
            ##
            ## experimental fast algorithm
            ##
            ##
           
              for (my $ai = $array_index; $ai < $all_features_count; ++$ai) {
#                my $feature = $all_features[$ai];
#                print "\$feature start = ", $feature->start(), ", \$ss_start = $ss_start, \$ss_stop = $ss_stop\n";
                if ($all_features[$ai]->start() >= $ss_start && $all_features[$ai]->start() < $ss_stop) {
                  next if (++$features_counted{$all_features[$ai]->id()} > 1); # don't count this feature if it's already been counted 2X    
                  print "\$feature $ai start = ", $all_features[$ai]->start(), ", \$ss_start = $ss_start, \$ss_stop = $ss_stop\n";
                  my $QDcount = $all_features[$ai]->attributes('QDcount');
                  $feat_count += $QDcount;
#                  print "feature id: ", $feature->id(), ", QDcount: ", $feature->attributes('QDcount'), ", feat_count = $feat_count\n";
                  
                  if (!$all_features[$ai]->strand()) {
                    next;
                  } elsif ($all_features[$ai]->strand() > 0) {
                    $plus += $QDcount;
                  } elsif ($all_features[$ai]->strand() < 0) {              
                    $minus += $QDcount;
                  }

#                  $running_count += $feat_count;
                  
#                   print "\t$refmol subsegment  [", $i, ", ", $i - 1 + $window, "] has $running_count features [ watson: $plus, crick: $minus ] of type '$featuretype'\n" if (($debug || $verbose) && $feat_count);
            
#                  printGFF($refmol,$featuretype,$i,$i - 1 + $window,$running_count,$window,$plus,$minus) if ($feat_count);
#                  $array_index = $ai + 1;
                } elsif ($all_features[$ai]->start() < $ss_start) {
                  $array_index = $ai + 1;
                  next;
                } else {
                  last;
                }
                     
              }
              
              $running_count += $feat_count;
              
              print "\t$refmol subsegment  [", $i, ", ", $i - 1 + $window, "] has $running_count features [ watson: $plus, crick: $minus ] of type '$featuretype'\n" if (($debug || $verbose) && $feat_count);
            
              printGFF($refmol,$featuretype,$i,$i - 1 + $window,$running_count,$window,$plus,$minus) if ($feat_count);

            } elsif ($algorithm eq 's') {
            ##
            ##
            ## standard algorithm -- slowest
            ##
            ##

              my $segment = $DB->segment( # Bio::DB::GFF::RelSegment
                                          -name   =>  $refmol,# maybe use name
                                          -start  =>  $ss_start,# $last_stop is 1 more than last stop
                                          -stop   =>  $ss_stop,
                                        );
#              $last_stop = $i + $window;
  
              my $features_iterator = $segment->features(# a list of Bio::DB::GFF::Feature objects
                                                          -types    =>  [$fmap{$featuretype}],
                                                          -iterator =>  1,
                                                        );
               # If -iterator is true, then the method returns a single scalar value consisting of a
               # Bio::SeqIO object.  You can call next_seq() repeatedly on this object to fetch each of
               # the features in turn.  If iterator is false or absent, then all the features are
               # returned as a list.
  
  
              while (my $feature = $features_iterator->next_seq()) {
  #             print "\$feature '", $feature->id(), "' isa '", ref($feature), "'\n";
                next if (++$features_counted{$feature->id()} > 1);
                my $QDcount = $feature->attributes('QDcount');
  #             $feat_count += $feature->attributes('QDcount');
                $feat_count += $QDcount;
  
  #              print "\t\$feature '", $feature->id(), "', QDcount = '$QDcount', strand = '", $feature->strand(), "'\n" if ($debug);
                
                # collect strand tally
                if (!$feature->strand()) {
                  next;
                } elsif ($feature->strand() > 0) {
                  $plus += $QDcount;
                } elsif ($feature->strand() < 0) {              
                  $minus += $QDcount;
                }
  
              }
              $running_count += $feat_count;
              
              print "\t$refmol subsegment  [", $i, ", ", $i - 1 + $window, "] has $running_count features [ watson: $plus, crick: $minus ] of type '$featuretype'\n" if (($debug || $verbose) && $feat_count);
        
              printGFF($refmol,$featuretype,$i,$i - 1 + $window,$running_count,$window,$plus,$minus) if ($feat_count);
              
            } elsif ($algorithm eq 'x') {
            ##
            ##
            ## experimental super-fast algorithm
            ##
            ##

              for (my $ai = $inner_array_index; $ai < $all_features_count; ++$ai) {
#                print "\$ai = $ai\n";
#                print "\$feature ", ffid($all_features[$ai]), " start = ", fstart($all_features[$ai]), ", \$ss_start = $ss_start, \$ss_stop = $ss_stop\n";
                if (fstart($all_features[$ai]) >= $ss_start && fstart($all_features[$ai]) <= $ss_stop) {
                  next if (++$features_counted{ffid($all_features[$ai])} > 1); # don't count this feature if it's already been counted 2X    

                  ++$array_index if (fstart($all_features[$ai]) < ($i + $window_0));# $array_index is outside of @windows loop

                  my $QDcount = fQDcount($all_features[$ai]);
                  print "\$feature $ai start = ", fstart($all_features[$ai]), ", QDcount = $QDcount, \$ss_start = $ss_start, \$ss_stop = $ss_stop\n" if ($debug);
                  $feat_count += $QDcount;
                  ++$fcount;
                  #print "feature id: ", $feature->id(), ", QDcount: ", $feature->attributes('QDcount'), ", feat_count = $feat_count\n";
                  
                  if (!fstrand($all_features[$ai])) {
                    next;
                  } elsif (fstrand($all_features[$ai]) eq '+') {
                    $plus += $QDcount;
                  } elsif (fstrand($all_features[$ai]) eq '-') {              
                    $minus += $QDcount;
                  }

#                  $running_count += $feat_count;
                  
                   print "\t[ watson: $plus, crick: $minus ]\n" if (($debug || $verbose) && $feat_count);
            
#                  printGFF($refmol,$featuretype,$i,$i - 1 + $window,$running_count,$window,$plus,$minus) if ($feat_count);
#                  $array_index = $ai + 1;
                  $inner_array_index = $ai + 1;
                } elsif (fstart($all_features[$ai]) < $ss_start) {
#                  $array_index = $ai + 1;
#                  print "next \$ai should be $array_index\n";
                  print "feature $ai start coord ", fstart($all_features[$ai]), " < $ss_start\n" if ($debug);
                  next;
                } else {
                  print "feature $ai start coord ", fstart($all_features[$ai]), " > $ss_stop\n" if ($debug);
                  last;
                }
                     
              }# end of for () that iterates through array of features
              
              $running_count += $feat_count;
#              $inner_array_index += $ai;
#              print "\t$refmol subsegment  [", $i, ", ", $i - 1 + $window, "] has $running_count ($fcount actual) features [ watson: $plus, crick: $minus ] of type '$featuretype'\n" if (($debug || $verbose) && $feat_count);
              print "\t$refmol subsegment $window window  [", $i, ", ", $i - 1 + $window, "] has $running_count ($fcount actual) features [ watson: $plus, crick: $minus ] of type '$featuretype'\n" if ($debug);
            
              printGFF($refmol,$featuretype,$i,$i - 1 + $window,$running_count,$window,$plus,$minus) if ($feat_count || $running_count);
#              printGFF($refmol,$featuretype,$i,$i - 1 + $window,$running_count,$window,$plus,$minus) if ($feat_count || $debug);
#              printGFF($refmol,$featuretype,$i,$i - 1 + $window,$running_count,$window,$plus,$minus) if ($feat_count);
#              last;
            }# end of if() statement for algorithm choice
          }# end of if() statement for QDcount 
        }# end of if() statement that discriminates windows
      }# end of foreach () $window
#      last if ($debug && $i >= 2);

  }# end of for () that walks down reference molecule

}
close(OUT);

sub printGFF {
  my $refmol = shift;
  my $featuretype = shift;
  my $start = shift;
  my $stop = shift;
  my $count = shift;
  my $window = shift;
  my $watson = shift;
  my $crick = shift;

  print OUT "$refmol\tQD\tQD", $featuretype, "_", $window, "\t$start\t$stop\t$count\t.\t.\tQD", $featuretype, " $refmol", ":", "QD; watson $watson; crick $crick;\n";

}

sub fast_fetch {
    #require CGRB::CGRBDB;
    require CGRBDB;
    my $refmol = shift;

    my %params = (
        host      =>  $dbhost,
        db        =>  $db,
        user      =>  $user,
        password  =>  $password,
    );

    my $db = CGRBDB->new(\%params);

    my $dbh = $db->dbh();
    my $typeid = get_typeid($db,$refmol);

    my $sth = $dbh->prepare("select d.fid, d.fref, d.fstart, d.fstop, d.fstrand, f.fattribute_value from `fdata` d, `fattribute` a, `fattribute_to_feature` f where d.fref = ? AND d.ftypeid = ? AND d.fid = f.fid AND f.fattribute_id = a.fattribute_id AND a.fattribute_name = 'QDcount' ORDER BY d.fstart ASC");
    $sth->bind_param(1,$refmol);
    $sth->bind_param(2,$typeid);
    my $arrayref = $db->dbAction($dbh,$sth,2);
#  print "number of results returned: '", scalar(@$arrayref), "'\n" if ($debug);
    return $arrayref;
}

sub get_typeid {
  my $db = shift;
  my $dbh = $db->dbh();
  my $sth = $dbh->prepare("select `ftypeid` from `ftype` where `fmethod` = ?");
  $sth->bind_param(1,$featuretype);
  my $arrayref = $db->dbAction($dbh,$sth,2);
  my $id = $arrayref->[0]->[0];
  return $id;
}

sub fstart {
  my $rowref = shift;
#  print "returning " . $rowref->[2] . "\n";
  return $rowref->[2];
}

sub fstop {
  my $rowref = shift;
  return $rowref->[3];
}

sub fQDcount {
  my $rowref = shift;
  return $rowref->[5];
}

sub ffid {
  my $rowref = shift;
  return $rowref->[0];
}

sub fstrand {
  my $rowref = shift;
  return $rowref->[4];
}
