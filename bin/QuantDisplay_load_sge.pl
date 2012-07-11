#!/usr/bin/env perl
#
use strict;
use Bio::DB::GFF;
use Getopt::Std;
use Cwd;
use vars qw/ $opt_h $opt_f $opt_d $opt_u $opt_p $opt_H $opt_b $opt_r $opt_l $opt_a $opt_A $opt_R $opt_v $opt_c $opt_q $opt_s /;

getopts('hf:du:p:H:b:r:R:l:aAvcq:s:');

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
my $queues = $opt_q;
my $stop = $opt_s;
my $start = $opt_l;

my $QD_script = "/home/cgrb/givans/bin/QuantDisplay_load.pl";
my $dir = cwd();

my $username = $ENV{USER};

if ($help) {

print <<HELP;

This script attempts to create bins in a gbrowse database
for user-specified feature types.  The resulting bins are
used by the QuantDisplay gbrowse plugin. The output file
from this script should be loaded into the primary gbrowse
database using bp_fast_load_gff.pl

$usage

ie: QuantDisplay_load_sge.pl -u brachy_cluster -b brachy4-gbrowse-dev -p password -H skynet.science.oregonstate.local -f perfect_match -R contig -a -c

Options

-h		print this help menu
-f		feature type (default = 'blah')
-l		list current feature types, then exit
-a		<feature type>
			perform analysis on all features of type <feature type>
			ie., contig, chromosome, assembly
-A		<feature type>
			list all features of type <feature type>, then exit
-R		reference molecule class (default = 'chromosome')
-r		reference molecule name (default = 'I')
-d		debugging mode
-v		verbose output to terminal
-u		user name for mysql database (default = 'yeast')
-p		use a password when connecting to MySQL database
-H		mysql hostname (default = pearson)
-b		mysql database name (default = 'yeast_chr1')
-c		for each feature, count based on QDcount attribute
-l		with default sorting, start at this reference molecule
-s		with default sorting, stop at this reference molecule

HELP
exit();
}

if ($debug) {

print <<DEBUG;

\$user = $user
\$password = $password
\$dbhost = $dbhost
\$db = $db
\$help = $help
\$debug = $debug
\$verbose = $verbose
\$featuretype = $featuretype
\$urefmol = $urefmol
\$usage = $usage
\$refclass = $refclass
\$QDcount = $QDcount
\$queues = $queues
\$stop = $stop
\$start = $start
\$QD_script = $QD_script
\$dir = $dir
\$username = $username


DEBUG
}

my $DB = Bio::DB::GFF->new(
														-adaptor		=>		'dbi::mysql',
														-dsn				=>		"dbi:mysql:" . $db . ";host=" . $dbhost,
														-user				=>		$user,
														-pass				=>		$password,
													);

my @refmols = ();
my @features = $DB->features($refclass);
foreach my $feature (@features) {
	push(@refmols,$feature->name());
}

my ($cnt,$job_interval,$job_threshold,$sleep_interval) = (0,1000,50,30);
foreach my $refmol (@refmols) {

	if ($start) {
		next unless ($refmol >= $start);
	}
	if ($stop) {
		last if ($refmol >= $stop);
	}

	++$cnt;
#	print "cnt = $cnt\n";
	
	my $gffout = $dir . "/" . $refmol . "_QD.gff";

	open(OUT,">$refmol" . "_QD_sge.sh") or die "can't open '$refmol" . "QD_sge.sh: $!";

#	print OUT "#\$ -o $ENV{HOME}/cluster/QDout$refmol\n#\$ -e $ENV{HOME}/cluster/QDerror$refmol\n#\$ -N QD_$refmol\n\n";
	print OUT "#\$ -o $ENV{HOME}/cluster/QDout$refmol\n#\$ -e $ENV{HOME}/cluster/QDerror$refmol\n#\$ -N $featuretype" . "$refmol\n\n";
	
	print OUT "$QD_script -u $user -p $password -H $dbhost -b $db -f $featuretype -r $refmol -R $refclass -c -o $gffout -X x\n\n";
	
	close(OUT);

	my $qsub_return;
	unless ($debug) {
		if ($queues) {
#			system("qsub -q $queues $refmol" . "_QD_sge.sh");

			open(QSUB, "qsub -q $queues $refmol" . "_QD_sge.sh |") or die "can't qsub: $!";

		} else {
#			system("qsub $refmol" . "_QD_sge.sh");

			open(QSUB, "qsub $refmol" . "_QD_sge.sh |") or die "can't open qsub: $!";

		}
		
		$qsub_return = <QSUB>;
		close(QSUB) or warn("can't close queue: $!");
		unlink("$refmol" . "_QD_sge.sh");
		
		if (! ($cnt % $job_interval)) {
		
			if ($qsub_return =~ /\sjob\s(\d+)\s/m) {
				my $jobid = $1;
				print "waiting for sge queue to clear before proceeding\n";
		
				QSTAT: while ($jobid) {
#					open(QSTAT, "qstat -j $jobid |") or die "I can't qstat -j $jobid : $!";
					open(QSTAT, "qstat -u $username -s p |") or die "I can't qstat -j $jobid : $!";
					my @qstat_response = <QSTAT>;
					close(QSTAT) or warn("can't close 'qstat -j $jobid' properly: $!");
				
					if (scalar(@qstat_response) > $job_threshold) {
						sleep($sleep_interval);
						redo QSTAT;
					} else {
						$jobid = 0;
					}
				}
				print "proceeding ...\n";
			} else {
				die "can't parse job number from sge return value\n'$qsub_return'\n\n";
			}
		} else {
			my $refmolid = $qsub_return;
			if ($qsub_return =~ /\"(.+)\"/) {
				$refmolid = "$1\n";
			}
			print $refmolid;
		}

		
#		unlink("$refmol" . "_QD_sge.sh");
		}
}
