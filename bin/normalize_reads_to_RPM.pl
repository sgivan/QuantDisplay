#!/usr/bin/env perl
#
use strict;
use Getopt::Long;
use File::Spec;

my ($user,$password,$database,$fsource,$debug,$help,$justsummary,$verbose,$install_path);
my ($dbhost,$dbport);

GetOptions(
    "user=s"        =>  \$user,
    "dbhost=s"      =>  \$dbhost,
    "dbport=i"      =>  \$dbport,
    "password=s"    =>  \$password,
    "database=s"    =>  \$database,
    "fsource=s"     =>  \$fsource,
    "justsummary"   =>  \$justsummary,
    "path=s"        =>  \$install_path,
    "debug"         =>  \$debug,
    "verbose"       =>  \$verbose,
    "help"          =>  \$help,
);

if ($help) {

print <<HELP;

--user
--password
--dbhost (default = lewis2.rnet.missouri.edu)
--dbport (default = 53307)
--database (default = 'QuantDisplay')
--fsource (default = 'GA2')
--justsummary
--path (default = $ENV{HOME}/projects/QuantDisplay)
--debug
--verbose
--help

HELP

exit();
}

#my $install_path = '/home/sgivan/projects/QuantDisplay';
$install_path = "$ENV{HOME}/projects/QuantDisplay" unless ($install_path);

$verbose = 1 if ($debug);
$database ||= 'QuantDisplay';
$fsource ||= 'GA2';
$dbhost ||= 'lewis2.rnet.missouri.edu';
$dbport ||= 53307;

if ($debug) {
    print "user = '$user'\npassword = '$password'\ndatabase = '$database'\nfsource = '$fsource'\n";
}

#open(STAT, "$install_path/sql/fdata_stats.mysql $user $password $database $fsource --silent |") or die "can't open fdata_stats.mysql: $!";
print "$install_path/sql/fdata_stats.mysql $user $password $dbhost $dbport $database $fsource --silent\n" if ($verbose);
open(STAT, "$install_path/sql/fdata_stats.mysql $user $password $dbhost $dbport $database $fsource --silent |") or die "can't open fdata_stats.mysql: $!";
my @sql = <STAT>;
close(STAT) or warn("can't close $install_path/sql/fdata_stats.mysql properly\n");

if ($verbose || $justsummary) {
    print "result of first query:\nt.fmethod, min(ff.fattribute_value), max(ff.fattribute_value), avg(ff.fattribute_value), sum(ff.fattribute_value), count(ff.fid)\n@sql\n";
}
exit() if ($justsummary);

foreach my $line (@sql) {
    my @vals = split/\s+/, $line;
    print "$install_path/sql/normalize_read_counts.mysql $user $password $database $vals[4] $fsource $vals[0]\n" if ($verbose);
    open(NRM, "$install_path/sql/normalize_read_counts.mysql $user $password $database $vals[4] $fsource $vals[0] |") or die "can't open normalize_read_counts.mysql: $!";
    my @rslt = <NRM>;
    close(NRM) or warn("couldn't close $install_path/sql/normalize_read_counts.mysql properly: $!");
    print "\@rslt = '@rslt'\n" if ($debug);
}

