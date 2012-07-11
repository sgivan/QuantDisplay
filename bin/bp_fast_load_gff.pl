#!/usr/bin/env perl
#
# $Id: bp_fast_load_gff.pl,v 3.7 2010/04/01 17:09:55 givans Exp $
#
eval 'exec /usr/bin/perl  -S $0 ${1+"$@"}'
    if 0; # not running under some shell
# $Id: bp_fast_load_gff.pl,v 3.7 2010/04/01 17:09:55 givans Exp $

use strict;
# use lib './blib/lib';
use DBI;
use IO::File;
use Getopt::Long;
use Bio::DB::GFF::Util::Binning 'bin';
#use Bio::DB::GFF::Adaptor::dbi::mysqlopt;
use Bio::DB::GFF::Adaptor::dbi::mysql;
use BerkeleyDB;

use constant MYSQL => 'mysql';

use constant FDATA      => 'fdata';
use constant FTYPE      => 'ftype';
use constant FGROUP     => 'fgroup';
use constant FDNA       => 'fdna';
use constant FATTRIBUTE => 'fattribute';
use constant FATTRIBUTE_TO_FEATURE => 'fattribute_to_feature';

my $DO_FAST = eval "use POSIX 'WNOHANG'; 1;";
$| = 1;

=head1 NAME

bp_fast_load_gff.pl - Fast-load a Bio::DB::GFF database from GFF files.

=head1 SYNOPSIS

  % bp_fast_load_gff.pl -d testdb dna1.fa dna2.fa features1.gff features2.gff ...

=head1 DESCRIPTION

This script loads a Bio::DB::GFF database with the features contained
in a list of GFF files and/or FASTA sequence files.  You must use the
exact variant of GFF described in L<Bio::DB::GFF>.  Various
command-line options allow you to control which database to load and
whether to allow an existing database to be overwritten.

This script is similar to load_gff.pl, but is much faster.  However,
it is hard-coded to use MySQL and probably only works on Unix
platforms due to its reliance on pipes.  See L<bp_load_gff.pl> for an
incremental loader that works with all databases supported by
Bio::DB::GFF, and L<bp_bulk_load_gff.pl> for a fast MySQL loader that
supports all platforms.

=head2 NOTES

If the filename is given as "-" then the input is taken from
standard input. Compressed files (.gz, .Z, .bz2) are automatically
uncompressed.

FASTA format files are distinguished from GFF files by their filename
extensions.  Files ending in .fa, .fasta, .fast, .seq, .dna and their
uppercase variants are treated as FASTA files.  Everything else is
treated as a GFF file.  If you wish to load -fasta files from STDIN,
then use the -f command-line swith with an argument of '-', as in 

    gunzip my_data.fa.gz | bp_fast_load_gff.pl -d test -f -

The nature of the load requires that the database be on the local
machine and that the indicated user have the "file" privilege to load
the tables and have enough room in /usr/tmp (or whatever is specified
by the \$TMPDIR environment variable), to hold the tables transiently.
If your MySQL is version 3.22.6 and was compiled using the "load local
file" option, then you may be able to load remote databases with local
data using the --local option.

About maxbin: the default value is 100,000,000 bases.  If you have
features that are close to or greater that 100Mb in length, then the
value of maxbin should be increased to 1,000,000,000.

The adaptor used is dbi::mysqlopt.  There is currently no way to
change this.

=head1 COMMAND-LINE OPTIONS

Command-line options can be abbreviated to single-letter options.
e.g. -d instead of --database.

   --database 		       Mysql database name
   --mach								 Mysql host
   --create              Reinitialize/create data tables without asking
   --local               Try to load a remote database using local data.
   --user                Username to log in as
   --fasta               File or directory containing fasta files to load
   --password            Password to use for authentication
   --maxbin              Set the value of the maximum bin size
   --nodownload          Don't download any of the current MySQL tables*
   --nooverwrite         Don't overwrite previously-generated BerkeleyDB files*
   --nodbtouch           Don't do anything to current MySQL database (mostly for testing)
   --noindex             Use this option if MySQL database indices have been inactivated (usually *not* the case)
   --lowmem              Links several large hashes to the file system to save LOTS of RAM
   --temp                Path to temporary file space
   --debug               Generate lots of debugging information to stdout

=head1 SEE ALSO

L<Bio::DB::GFF>, L<bulk_load_gff.pl>, L<load_gff.pl>

=head1 AUTHOR

Lincoln Stein, lstein@cshl.org

Copyright (c) 2002 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut

package Bio::DB::GFF::Adaptor::faux;

use Bio::DB::GFF::Adaptor::dbi::mysqlopt;
use vars '@ISA';
@ISA = 'Bio::DB::GFF::Adaptor::dbi::mysqlopt';

sub insert_sequence {
  my $self = shift;
  my ($id,$offset,$seq) = @_;
  print join "\t",$id,$offset,$seq,"\n";
}

package main;

my ($DSN,$CREATE,$USER,$PASSWORD,$FASTA,$FAILED,$LOCAL,%PID,$MAX_BIN,$HOST,$ND,$NO,$NODB,$NI,$DEBUG,$LOWMEM,$TEMP);
#my $path_to_temp = '/usr/local/scratch';

if ($DO_FAST) {
#	print "DO_FAST = '$DO_FAST'\n";
  $SIG{CHLD} = sub {
    while ((my $child = waitpid(-1,&WNOHANG)) > 0) {
      delete $PID{$child} or next;
      $FAILED++ if $? != 0;
    }
  }
};

$SIG{INT} = $SIG{TERM} = sub {cleanup(); exit -1};

GetOptions (
	'database:s'    => \$DSN,
	'create'        => \$CREATE,
	'user:s'        => \$USER,
	'local'         => \$LOCAL,
	'password:s'    => \$PASSWORD,
	'fasta:s'       => \$FASTA,
	'maxbin:s'      => \$MAX_BIN,
	'mach:s'				=>	\$HOST,
	'nodownload'    =>  \$ND,
	'nooverwrite'   =>  \$NO,
	'nodbtouch'     =>  \$NODB,
	'noindex'       =>  \$NI,
	'lowmem'        =>  \$LOWMEM,
	'temp=s'          =>  \$TEMP,
	'debug'         =>  \$DEBUG,
) or (system('pod2text',$0), exit -1);

$DSN ||= 'test';

my (@auth,$AUTH);
if (defined $USER) {
  push @auth,(-user=>$USER);
  $AUTH .= " -u$USER";
}
if (defined $PASSWORD) {
  push @auth,(-pass=>$PASSWORD);
  $AUTH .= " -p$PASSWORD";
}

if (!$HOST) {
	$HOST = 'localhost';
}

#my $path_to_temp = '/usr/local/scratch';
my $path_to_temp = '/tmp';
$path_to_temp = $TEMP if ($TEMP);

#
# original Bio::DB::GFF object initialization
#
#my $db = Bio::DB::GFF->new(-adaptor=>'faux',-dsn => $DSN,@auth)
#  or die "Can't open database: ",Bio::DB::GFF->error,"\n";

#
# Scott Givan modified
#
# my $db = Bio::DB::GFF->new(-adaptor=>'dbi::mysql',-dsn => $DSN,@auth)
#   or die "Can't open database: ",Bio::DB::GFF->error,"\n";
#my $db = Bio::DB::GFF->new(-adaptor=>'dbi::mysql',-dsn => "dbi:mysql:database=$DSN;host=pearson.science.oregonstate.local;user=brachy_cluster;password=brachypodium") or die "Can't open database: ",Bio::DB::GFF->error,"\n";

#my $db = Bio::DB::GFF->new(-adaptor=>'dbi::mysql',-dsn => "dbi:mysql:database=$DSN;host=$HOST;port=53307;user=$USER;password=$PASSWORD") or die "Can't open database: ",Bio::DB::GFF->error,"\n";
my $db = Bio::DB::GFF->new(-adaptor=>'dbi::mysql',-dsn => "dbi:mysql:database=$DSN;host=$HOST;port=53307;user=$USER;password=$PASSWORD;") or die "Can't open database: ",Bio::DB::GFF->error,"\n";

#
# end of modification
#

if ($CREATE) {
  $MAX_BIN ? $db->initialize(-erase=>1,-MAX_BIN=>$MAX_BIN) : $db->initialize(1);
}

foreach (@ARGV) {
  $_ = "gunzip -c $_ |" if /\.gz$/;
  $_ = "uncompress -c $_ |" if /\.Z$/;
  $_ = "bunzip2 -c $_ |" if /\.bz2$/;
}
my(@fasta,@gff);
foreach (@ARGV) {
  if (/\.(fa|fasta|dna|seq|fast)$/i) {
    push @fasta,$_;
  } else {
    push @gff,$_;
  }
}
@ARGV = @gff;
push @fasta,$FASTA if defined $FASTA;

# initialize state variables
my $FID     = 1;
my $GID     = 1;
my $FTYPEID = 1;
my $ATTRIBUTEID = 1;
my %GROUPID     = ();
my %FTYPEID     = ();
my %ATTRIBUTEID = ();
my %DONE        = ();
my $FEATURES    = 0;
my $BDB_flags = $NO ? DB_CREATE : DB_CREATE|DB_TRUNCATE;

print STDERR "flags passed to BerkeleyDB: '$BDB_flags'\n";

if ($LOWMEM) {

  tie(%GROUPID, 'BerkeleyDB::Btree',
  #  	-Filename	=>	'/data/scratch/groupid',
      -Filename	=>	"$path_to_temp/groupid",
  #	  -Flags		=>	DB_CREATE|DB_TRUNCATE,
      -Flags    =>  $BDB_flags,
    ) or die "can't tie $path_to_temp/groupid': $!";
  
  tie(%DONE, 'BerkeleyDB::Btree',
  #	-Filename	=>	'/data/scratch/done',
    -Filename	=>	"$path_to_temp/done",
  #	-Flags		=>	DB_CREATE|DB_TRUNCATE,
    -Flags		=>	$BDB_flags,
    ) or die "can't tie $path_to_temp/done: $!";

}

$FID         = 1 + get_max_id($db->dbh(),'fdata','fid');
$GID         = 1 + get_max_id($db->dbh(),'fgroup','gid');
$FTYPEID     = 1 + get_max_id($db->dbh(),'ftype','ftypeid');
$ATTRIBUTEID = 1 + get_max_id($db->dbh(),'fattribute','fattribute_id');

print STDERR "\$FID = $FID\n\$GID = $GID\n\$FTYPEID = $FTYPEID\n\$ATTRIBUTEID = $ATTRIBUTEID\n";

# call load_tables()
# retrieves current content from db tables fgroup, ftype, fattribute
#
unless ($ND || $CREATE) {
  load_tables($db->dbh);# retrieves current content from db tables fgroup, ftype, fattribute
  print STDERR "tables loaded successfully\n";
} else {
  print STDERR "options inactivate load_tables()\n";
  get_ids($db->dbh(),\%DONE,\%ATTRIBUTEID,'fattribute','fattribute_id','fattribute_name');# these is usually a relatively small table
  get_ids($db->dbh(),\%DONE,\%FTYPEID,'ftype','ftypeid','fsource','fmethod');
}


# open up pipes to the database
my (%FH,%COMMAND);
my $MYSQL = MYSQL;
#my $tmpdir = $ENV{TMPDIR} || $ENV{TMP} || '/usr/tmp';# use /local/cluster/tmp if problems
my $tmpdir = $ENV{TMPDIR} || $ENV{TMP} || '/tmp';# use /local/cluster/tmp if problems
#my @files = (FDATA,FTYPE,FGROUP,FDNA,FATTRIBUTE,FATTRIBUTE_TO_FEATURE);

my @files = (FDATA,FATTRIBUTE_TO_FEATURE);
open_pipes(\@files);


print STDERR "Fast loading enabled\n" if $DO_FAST;
print STDERR "Loading fdata and fattribute_to_feature tables\n" if ($DO_FAST);

my ($count,$fasta_sequence_id,$gff3,$loopcnt);
#my (%fgroup,%ftype,%fattribute);
my (%fgroup,%ftype);
my (@fgroup,@ftype,@fattribute);

while (<>) {
  chomp;
  my ($ref,$source,$method,$start,$stop,$score,$strand,$phase,$group);
  if (/^>(\S+)/) {  # uh oh, sequence coming
      $fasta_sequence_id = $1;
      last;
  } elsif (/^\#\#gff-version\s+3/) {
    $gff3++;
    next;
  } elsif (/^\#\#\s*sequence-region\s+(\S+)\s+(\d+)\s+(\d+)/i) { # header line
    ($ref,$source,$method,$start,$stop,$score,$strand,$phase,$group) = 
      ($1,'reference','Component',$2,$3,'.','.','.',$gff3 ? "ID=Sequence:$1": qq(Sequence "$1"));
  } elsif (/^\#/) {
    next;
  } else {
    ($ref,$source,$method,$start,$stop,$score,$strand,$phase,$group) = split "\t";
  }
  next unless defined $ref;

  last if ($loopcnt++ == 10 && $DEBUG);

  $FEATURES++;

  $source = '\N' unless defined $source;
  $score  = '\N' if $score  eq '.';
  $strand = '\N' if $strand eq '.';
  $phase  = '\N' if $phase  eq '.';

  my ($group_class,$group_name,$target_start,$target_stop,$attributes) = Bio::DB::GFF->split_group($group,$gff3);
  $group_class  ||= '\N';
  $group_name   ||= '\N';
  $target_start ||= '\N';
  $target_stop  ||= '\N';
  $method       ||= '\N';
  $source       ||= '\N';

  my ($fid,$gid,$ftypeid);
  if ($ND) {
      if (! defined($GROUPID{join $;,($group_class,$group_name)})) {
#        print "\t\t\tretrieving group id from database\n";
#        $GROUPID{join $;,($group_class,$group_name)} = get_groupid($db->dbh,$group_class,$group_name) || $GID++;
        my $tgid = get_groupid($db->dbh,$group_class,$group_name);
        if ($tgid != -99) {
#        if (get_groupid($db->dbh,$group_class,$group_name)) {
          $GROUPID{join $;,($group_class,$group_name)} = $tgid;
        } else {
          $GROUPID{join $;,($group_class,$group_name)} = $GID++;
          #die "can't determine group ID for class '$group_class', name '$group_name'\n";
        }
      }
  }
  
  $fid     = $FID++;
#    $gid     = $GROUPID{$group_class,$group_name} ||= $GID++;
#    $ftypeid = $FTYPEID{$source,$method}          ||= $FTYPEID++;
  $gid = $GROUPID{join $;,($group_class,$group_name)} ||= $GID++;
  $ftypeid = $FTYPEID{join $;,($source,$method)} ||= $FTYPEID++;
  

  my $bin = bin($start,$stop,$db->min_bin);
	# new -- add call to flush for FH's that were losing DB connection
  $FH{ FDATA()  }->print(    join("\t",$fid,$ref,$start,$stop,$bin,$ftypeid,$score,$strand,$phase,$gid,$target_start,$target_stop),"\n"   ) unless ($NODB);
  print("fdata: ",join("\t",$fid,$ref,$start,$stop,$bin,$ftypeid,$score,$strand,$phase,$gid,$target_start,$target_stop),"\n") if ($DEBUG);
	if (!$DONE{"fgroup$;$gid"}++) {
#	   	$FH{ FGROUP() }->print(    join("\t",$gid,$group_class,$group_name),"\n"              );# unless $DONE{"fgroup$;$gid"}++;
# 		$FH{ FGROUP() }->flush();
#		$fgroup{$gid} = join("\t",$gid,$group_class,$group_name);# ?? is this ever used?
		push(@fgroup, join("\t",$gid,$group_class,$group_name)) unless ($GROUPID{join $;,($group_class,$group_name)} == -99);
	} else {
#	  print STDERR "\$DONE{\"fgroup$;$gid\"} = '", $DONE{"fgroup$;$gid"}, "'\n";
	}
	if (!$DONE{"ftype$;$ftypeid"}++) {
#   		$FH{ FTYPE()  }->print(    join("\t",$ftypeid,$method,$source),"\n"                   );# unless $DONE{"ftype$;$ftypeid"}++;
# 		$FH{ FTYPE()  }->flush();
		$ftype{$ftypeid} = join("\t",$ftypeid,$method,$source);
		push(@ftype, join("\t",$ftypeid,$method,$source));
	}

  foreach (@$attributes) {
    my ($key,$value) = @$_;
    my $attributeid = $ATTRIBUTEID{$key} ||= $ATTRIBUTEID++;
    if (!$DONE{"fattribute$;$attributeid"}++) {
  #     		$FH{ FATTRIBUTE() }->print( join("\t",$attributeid,$key),"\n"                       );# unless $DONE{"fattribute$;$attributeid"}++;
  # 		$FH{ FATTRIBUTE() }->flush();
  #		$fattribute{$attributeid} = join("\t",$attributeid,$key);# ?? I don't think I ever use %fattribute
      push(@fattribute, join("\t",$attributeid,$key));
    }
    $FH{ FATTRIBUTE_TO_FEATURE() }->print( join("\t",$fid,$attributeid,$value),"\n") unless ($NODB);
    print STDERR "fattribute_to_feature: ", join("\t",$fid,$attributeid,$value) . "\n" if ($DEBUG);
  }

  if ( $FEATURES % 1000 == 0) {
    print STDERR "$FEATURES features parsed...";
    print STDERR -t STDOUT && !$ENV{EMACS} ? "\r" : "\n";
  }
}

print STDERR "Closing fdata and fattribute_to_feature pipes\n" if ($DO_FAST);
close_pipes(\@files);

print STDERR "Done ...\nOpening fgroup, ftype and fattribute pipes\n" if ($DO_FAST);
@files = (FGROUP,FTYPE,FATTRIBUTE);
open_pipes(\@files);

print STDERR "Loading fgroup table\n" if ($DO_FAST);
unless ($NODB) {
  foreach my $entry (@fgroup) {
    $FH{ FGROUP() }->print($entry . "\n");
  }
} else {
  print STDERR "not touching fgroup table\n";
}
if ($DEBUG) {
  foreach my $entry (@fgroup) {
    print("fgroup: '" . $entry . "'\n");
  }
}
print STDERR "Done...\nLoading ftype table\n" if ($DO_FAST);
print STDERR "not touching ftype table\n" if ($DO_FAST && $NODB);
foreach my $entry (@ftype) {
	$FH{ FTYPE() }->print($entry . "\n") unless ($NODB);
	print("ftype: " . $entry . "\n") if ($DEBUG);
}

print STDERR "Done...\nLoading fattribute table\n" if ($DO_FAST);

unless ($NODB) {
  foreach my $entry (@fattribute) {
    $FH{ FATTRIBUTE() }->print($entry . "\n");
  }
} else {
  print STDERR "not touching fattribute table\n";
}
if ($DEBUG) {
  foreach my $fattribute (@fattribute) {
    print("fattribute: " . $fattribute . "\n");
  }
}
print STDERR "Done...\n" if ($DO_FAST);
print STDERR "Closing fgroup, ftype, fattribute pipes\n" if ($DO_FAST);
print STDERR "If error messages are generated, reconcile data with fdata, fgroup and ftype tables\n";
print STDERR "When an error message is generated, it usually reflects a problem with the ftype table\n \
This might require manual entry of the row, which isn't ususally very difficult.";



if (defined $fasta_sequence_id) {
  warn "Preparing embedded sequence....\n";
  my $old = select($FH{FDNA()});
  $db->load_sequence('ARGV',$fasta_sequence_id);
  warn "done....\n";
  select $old;
}

for my $fasta (@fasta) {
  warn "Loading fasta ",(-d $fasta?"directory":"file"), " $fasta\n";
  my $old = select($FH{FDNA()});
  my $loaded = $db->load_fasta($fasta);
  warn "$fasta: $loaded records loaded\n";
  select $old;
}

my $success = 1;
$_->close foreach values %FH;

if (!$DO_FAST) {
  warn "Loading feature data.  You may see duplicate key warnings here...\n";
  $success &&= system($COMMAND{$_}) == 0 foreach @files;
}

# wait for children
while (%PID) {
  sleep;
}
$success &&= !$FAILED;

cleanup();

if ($success) {
  print "SUCCESS: $FEATURES features successfully loaded\n";
  exit 0;
} else {
  print "FAILURE: Please see standard error for details\n";
  exit -1;
}

exit 0;

sub cleanup {
  foreach (@files) {
    unlink "$tmpdir/$_.$$";
  }
}

# load copies of some of the tables into memory
sub load_tables {
  my $dbh = shift;
  print STDERR "loading normalized group, type and attribute information...";
#  $FID         = 1 + get_max_id($dbh,'fdata','fid');
#  $GID         = 1 + get_max_id($dbh,'fgroup','gid');
#  $FTYPEID     = 1 + get_max_id($dbh,'ftype','ftypeid');
#  $ATTRIBUTEID = 1 + get_max_id($dbh,'fattribute','fattribute_id');
	print STDERR "\nloading fgroup table into memory\n";
  get_ids($dbh,\%DONE,\%GROUPID,'fgroup','gid','gclass','gname');
	print STDERR "OK.  Loading ftype table into memory\n";
  get_ids($dbh,\%DONE,\%FTYPEID,'ftype','ftypeid','fsource','fmethod');
	print STDERR "OK.  Loading fattribute table into memory\n";
  get_ids($dbh,\%DONE,\%ATTRIBUTEID,'fattribute','fattribute_id','fattribute_name');
  print STDERR "ok\n";
}

sub get_max_id {
  my $dbh = shift;
  my ($table,$id) = @_;
  my $sql = "select max($id) from $table";
  my $result = $dbh->selectcol_arrayref($sql) or die $dbh->errstr;
  $result->[0];
}

sub get_ids { # this is called from load_tables() only
  my $dbh = shift;
  my ($done,$idhash,$table,$id,@columns) = @_;
  my $columns = join ',',$id,@columns;
  my $sql = "select $columns from $table";
  my $sth = $dbh->prepare($sql) or die $dbh->errstr;
	print STDERR "\nfetching data from $table ['$sql'] ...\n";
  $sth->execute or die $dbh->errstr;
	print STDERR "OK.  Now creating data structure ...\n";
  while (my($id,@cols) = $sth->fetchrow_array) {
    my $key = join $;,@cols;
    $idhash->{$key} = $id;
    $done->{$table,$id}++;
# 		if ( $id % 1000 == 0) {
# 			print STDERR "\tid: $id\n";
# 		}
  }
	print STDERR "OK\n";
}

sub get_ftypeid {
  my $dbh = shift;
  my ($fsource,$fmethod) = @_;
  return 0 unless ($fmethod && $fsource);
#  print "get_ftypeid() querying the database: \$fmethod = '$fmethod', \$fsource = '$fsource'\n";
  my $sql = "select `ftypeid` from `ftype` where `fmethod` = ? AND `fsource` = ?";
  my $sth = $dbh->prepare($sql) or die $dbh->errstr;
  $sth->bind_param(1,$fmethod);
  $sth->bind_param(2,$fsource);
  $sth->execute() or die $dbh->errstr;
  my $rtn = $sth->fetchrow_arrayref();
  $sth->finish();
#  print "\$rtn isa '", ref($rtn), "'\n";
  if (ref($rtn) eq 'ARRAY') {
#    print "get_ftypeid() returning a value\n";
    return $rtn->[0];
  } else {
#    print "get_ftypeid() returning 0\n";
    return 0;
  }
}

sub get_fattributeid {
  my $dbh = shift;
  my $fattribute_name = shift;
  return 0 unless ($fattribute_name);
  
  my $sql = "select `fattribute_id` from `fattribute` where `fattribute_name` = ?";
  my $sth = $dbh->prepare($sql) or die $dbh->errstr;
  $sth->bind_param(1,$fattribute_name);
  $sth->execute() or die $dbh->errstr;
  my $rtn = $sth->fetchrow_arrayref();
  $sth->finish();
  
  if (ref($rtn) eq 'ARRAY') {
    return $rtn->[0];
  } else {
    return 0;
  }
}

sub get_groupid {
  my $dbh = shift;
  my ($gclass,$gname) = @_;
  return 0 unless ($gclass && $gname);
#  print "\n\n\n\t\t\tget_groupid(): gclass = '$gclass', gname = '$gname'\n";
  
  my $sql = "select `gid` from `fgroup` where `gclass` = ? AND `gname` = ?";
  my $sth = $dbh->prepare($sql) or die $dbh->errstr;
  $sth->bind_param(1,$gclass);
  $sth->bind_param(2,$gname);
  $sth->execute() or die $dbh->errstr;
  my $rtn = $sth->fetchrow_arrayref();
  $sth->finish();
  
  if (ref($rtn) eq 'ARRAY') {
#    print "\t\t\treturning '", $rtn->[0], "'\n\n\n";
    return $rtn->[0];
  } else {
    return -99;
  }
}


sub open_pipes {
	my $file_names = shift;

	foreach (@$file_names) {
		my $file = "$tmpdir/$_.$$";
		print STDERR "creating load file $file...";
#		$DO_FAST &&= (system("mkfifo $file") == 0);  # for system(), 0 = success

		if ($DO_FAST) {
			my $rtn = system("mkfifo $file");
			if ($rtn) {
				print STDERR "mkfifo $file failed: $!\n";
				exit(1);
			} else {
				$DO_FAST = 1;
			}
		}

		print STDERR "ok (\$DO_FAST = '$DO_FAST')\n";
		my $delete = $CREATE ? "delete from $_" : '';
		my $local  = $LOCAL ? 'local' : '';
	
	#
	# original mysql commnad
	#
	#   my $command =<<END;
	# $MYSQL $AUTH
	# -e "lock tables $_ write; $delete; load data $local infile '$file' replace into table $_; unlock tables"
	# $DSN
	# END
	# ;
	
	#
	# Scott Givan modifications
	#
	
my $command =<<END;
$MYSQL $AUTH
-e "lock tables $_ write; $delete; load data $local infile '$file' replace into table $_; unlock tables"
-h $HOST $DSN
END
;
	
	
	#
	# end of modifications
	#
	
		$command =~ s/\n/ /g;
		$COMMAND{$_} = $command;
	
	#	print "command: '$command'\n";
    #    exit();
	#	next;
	
		if ($DO_FAST) {
			if (my $pid = fork) {
				$PID{$pid} = $_;
				print STDERR "pausing for 0.5 sec..." if $DO_FAST;
				select(undef,undef,undef,0.50); # work around a race condition
				print STDERR "select() ok\n";
			} else {  # THIS IS IN CHILD PROCESS
				die "Couldn't fork: $!" unless defined $pid;
				exec $command || die "Couldn't exec: $!";
				exit 0;
			}
		}
		print STDERR "opening load file for writing...";
		$FH{$_} = IO::File->new($file,'>') or die $_,": $!";
		print STDERR "file opened ok\n";
		$FH{$_}->autoflush;
	}
}

sub close_pipes {
	my $pipes = shift;

	foreach my $pipe (@$pipes) {
		$FH{$pipe}->close();
	}
}

__END__
