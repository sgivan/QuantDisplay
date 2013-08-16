package Bio::Graphics::Browser2::Plugin::QuantDisplay;
# 
# 
#     QuantDisplay -- Configurable Histograms for gbrowse
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
#   Note that I must modify /usr/dev/lib/x86_64-linux-thread-multi/Bio/Graphics/Browser/PluginSet.pm
#   line 125 or error output is generated. This seems to be related to some configuration options
#   having unitialized values, but I haven't been able to identify the section of QuantDisplay.pm
#   that is contributing to this problem. So, I modified the above line to stop the error_log message.
#
#


use strict;
use Bio::Graphics::Browser2::Plugin;
#use Bio::Graphics::Browser2::Plugin::Util;
use Bio::DB::GFF;
use CGI qw(:standard *table);
use vars '$VERSION','@ISA';
$VERSION = '2.10';# must arbitrarily update this after moving to git

@ISA = qw(Bio::Graphics::Browser2::Plugin);

my (%SITES,@SITES);
#my @BINS = (50,100,500,1000,5000,10000,25000,50000,75000,100000,250000,500000,750000,1000000);
my @BINS = (50,100,1000,5000,10000,25000,100000,250000);
my $FCOUNT = 0;

my $debug = 0;
if ($debug) {
  open(LOG,">>/tmp/QuantDisplay.log") or warn "can't open QuantDisplay.log";
  print LOG "\n\n" . "+" x 10 . "\nQuantDisplay\t" . scalar(localtime) . "\n";
}

#sub type { return 'annotator'; }
sub type { 'annotator' }
#sub verb { return 'Plot'; }
#sub verb { 'Draw' }

sub init {
  my $self = shift;
  print LOG "init()\n" if ($debug);
}

sub name {
  my $self = shift;
  print LOG "name()\n" if ($debug);
  #my $config = $self->configuration;
  my $config = {};
  #my $config = $self->_configure_browser();
  $self->_configure_browser($config);

  if ($debug) {
    my ($package, $filename, $line) = caller();
    print LOG "caller(): $package, $filename, $line\n";

    print LOG "\nin name(), config:\n";
    foreach my $key (keys %$config) {
        print LOG "$key -> " . $config->{$key} . "\n";
    }
  }

  return $config->{data_name} || 'unknown';
# return "Illumina Reads";
}

sub description {
  my $self = shift;
  print LOG "description()\n" if ($debug);
  my $config = $self->configuration();
  #my $bc = $self->_configure_browser($config);
  $self->_configure_browser($config);
  if ($debug) {
	print LOG "\$config isa '", ref($config), "'\n";
  }

  my $version = $VERSION;
  $version =~ s/\$//g;
  $version =~ s/Revision:\s//;

  my $content = "<p>This is a gbrowse plugin to display quantitative data for a genome segment.</p>";

  if ($config->{content_description}) {
    $content .= "<h3 style=\"padding-top: 15px;\">Description of data</h3>";
    $content .= "<p>" . $config->{content_description} . "</p>";
  }

  $content .= "<p style=\"padding-top: 20px;\">QuantDisplay version $version</p><div style=\"height: 25px;\"></div>";

  return $content;
}

sub annotate {
	my $self = shift;
	my $segment = shift;
	print LOG "\nannotate()\n" if ($debug);
	my $config  = $self->configuration;
	my $ref = $segment->seq_id();
	return undef unless ($config->{on});
	$self->configure_sites();

	if (0) {
		print LOG "\n\n";
		print LOG "current configuration from call to configuration():\n";
		print LOG "\$self isa '", ref($self), "'\n";
		print LOG "\$config isa '", ref($config), "'[$config]\n";
		foreach my $key (keys %$config) {
			print LOG "\$key = '$key'\n";
			if ($config->{$key}) {
				print LOG "$key -> ", $config->{$key}, "\n";
			} else {
				print LOG "config '$key' has no setting\n";
			}
		}
		print LOG "\n\n";
	}

	$self->_configure_browser($config);

	my $seglength = $segment->length();
	my $window = $config->{window};
	my $max_detail = $config->{max_detail} || 0;
	#  my $min_score = $config->{min_score} || '0';
	#my $max_score = $config->{max_score} || undef;
	my $max_hscore = $config->{max_hscore} || undef;
	my $graph_height = $config->{graph_height};
	my $clip = $config->{clip} || '0';
	my $state = 'n/a';
	my $render = 'n/a';
	$render = $self->renderer();
	$state = $render->request();
	my $multiplier = $render->details_mult() || 'n/a';	

	if ($debug) {
		print LOG "\nseglength = '$seglength'\nwindow = '$window'\nmax_detail = '$max_detail'\n \
			  max_hscore = '$max_hscore'\ngraph_height = '$graph_height'\nclip = '$clip\n \
			  multiplier = '$multiplier'\nstate is '", ref($state), "'\nrender is '", ref($render), "'\n";
	}



  if ($debug) {
    my $page_settings = $self->page_settings();
    while(my($key,$value) = each %$page_settings) {
      print LOG "page_settings '$key' => '$value'\n";
      if ($key eq 'track_collapsed') {
        print LOG "printing collapsed tracks:\n";
        while (my($key2,$value2) = each %$value) {
          print LOG "\ttrack '$key2' = '$value2'\n";
        }
      }
    }
  }
# my @BINS = (50,100,1000,5000,10000,25000,100000,250000);
  my $bin_width;
# print LOG "window = '$bin_width'\n" if ($debug);
  if ($window !~ /\d+/) {
    if ($seglength > 50000000) {
      $bin_width = $BINS[7];
    } elsif ($seglength >= 10000000) {
      $bin_width = $BINS[6];
    } elsif ($seglength >= 5000000) {
#      $bin_width = 25000;
      $bin_width = $BINS[5];
    } elsif ($seglength >= 1000000) {
#      $bin_width = 10000;
      $bin_width = $BINS[4];
    } elsif ($seglength >= 500000) {
#      $bin_width = 5000;
      $bin_width = $BINS[3];
    } elsif ($seglength >= 100000) {
#      $bin_width = 1000;
      $bin_width = $BINS[2];
    } elsif ($seglength >= 10000) {
#      $bin_width = 100;
      $bin_width = $BINS[1];
    } else {
#      $bin_width = 50;
      $bin_width = $BINS[0];
    }
  } else {
    $bin_width = $window;
  }
  
  if ($debug) {

    print LOG "bin_width = $bin_width\n";
    print LOG "window = $window\n";
    print LOG "\$self isa '", ref($self), "'\n";
    print LOG "\$segment isa '", ref($segment), "'\n";
    print LOG "\t", $segment->start(), " - ", $segment->stop(), "\n";
#    print LOG "\tfeature count: ", $segment->feature_count(), "\n\n";
    print LOG "\$config isa '", ref($config), "'\n";
#   my $datasource = $config->{QD_datasource};
    my $datasource = $self->_array_to_hash($config->{QD_datasource});

    foreach my $key (keys %$datasource) {
      print LOG "dataset: '$key', datasource: '", $datasource->{$key}, "'\n";
    }
    print LOG "\n\n";

    if (ref($config) eq 'HASH') {
        print LOG "config hashref contains:\n";
      while (my($key,$value) = each %$config) {
        $key = 'n/a' unless($key);
        $value = 'n/a' unless ($value);
        print LOG "\t'$key'\t=>\t'$value'\n";
      }
      print LOG "\n\n";
    }
  }
  
  $self->_display_order();
    
  if ($debug) {
    print LOG "\ncontent of \%SITES:\n";
    while (my($key,$value) = each %SITES) {
      print LOG "'$key' : '$value'\n";
    }
    print LOG "\n";
  }
  
#  my $feature_list   = Bio::Graphics::FeatureFile->new();
  my $feature_list = $self->new_feature_list;
  print LOG "\$feature_list isa '", ref($feature_list), "'\n" if ($debug);
  print LOG "Bio::Graphics::FeatureFile->version(): '", Bio::Graphics::FeatureFile->version(), "'\n" if ($debug);
  
  foreach my $qdfeat (sort { $SITES{$a} <=> $SITES{$b} } keys %SITES) {
    next unless ($config->{$qdfeat});
    print LOG "generating display for '$qdfeat'\n" if ($debug);
    my @binblahs = ();
    my $type = 'generic';
    my $strands = 0;
    $strands = 1 if ($config->{"$qdfeat" . "_strands"});
    
    if ($seglength > $max_detail + 1 || $config->{no_detail}) { # gbrowse 1.69 added 1nt when user clicked on horiz. scale, 
                                                                # which could cause display to change to histogram view

      print LOG "generating histogram display\n" if ($debug);

    my ($db2,$segment2);
    $self->_db_handle(\$db2,$config);
    print LOG "creating new segment using: ", $segment->refseq(), ", ", $segment->start(), ", ", $segment->stop(), "\n" if ($debug);
    $segment2 = $db2->segment(
        -name   =>  $segment->refseq(),
        -start  =>  $segment->start(),
        -stop   =>  $segment->stop(),
    );
    my $segment_orig = $segment;
    $segment = $segment2;
    print LOG "new segment isa ", ref($segment), "\n" if ($debug);


#    my @tracktypes = ("QDCF-1_100:QD", "QDCF-2_100:QD", "QDCF-3_100:QD");
    my ($combined,@tracktypes) = ();
    if ($qdfeat =~ /!/) {
        $combined = 1;
        for my $qdfeat (split /!/, $qdfeat) {
            $qdfeat =~ s/QD//;
            push(@tracktypes, "QD" . $qdfeat . "_" . $bin_width . ":QD");
        }
    } else {
            push(@tracktypes, "QD" . $qdfeat . "_" . $bin_width . ":QD");
    }
      #my @feats = $segment->features( -type => "QD" . $qdfeat . "_" . $bin_width . ":QD"); # original
      my @feats = $segment->features( -types => \@tracktypes );
    print LOG "number of features using \@tracktypes: " . scalar(@feats) . "\n" if ($debug);

    @feats = sort { $a->start() <=> $b->start() } @feats;
    my @combined_feats = ();
    push(@combined_feats,shift(@feats));
    print LOG "\@combined_feats: '" . scalar(@combined_feats) . "', \@feats: '" . scalar(@feats) . "'\n" if ($debug);
    for my $feat (@feats) {
        if ($combined_feats[$#combined_feats] && $combined_feats[$#combined_feats]->start() == $feat->start()) {
            $combined_feats[$#combined_feats]->score($combined_feats[$#combined_feats]->score() + $feat->score());
        } else {
            push(@combined_feats,$feat);
        }
    }
    @feats = @combined_feats;

      if ($strands) {
        my @nfeats = ();
        foreach my $feat (@feats) {
          my $nfeat = $feat->clone();
          $feat->score($feat->attributes('watson'));
          $nfeat->score(0 - $feat->attributes('crick')) if ($feat->attributes('crick'));
          push(@nfeats,$nfeat);
        }
        push(@feats,@nfeats);
      }
      next unless (@feats);

      my $dataset_display_name = $self->_array_to_hash( $config->{dataset_display_name} );
      my ($cnt,$key_addn) = (0,$dataset_display_name->{$qdfeat} || $qdfeat);

      $type = $feats[0]->type()->asString();
      $type =~ s/:.+//;# this is to simplify type name
    if ($combined) {
        $type = $qdfeat;
    }
    #$key_addn = "CF-all";
      print LOG "\$type = '$type'\n" if ($debug);
    
      $feature_list->add_type($type => {
          glyph       =>  'qdplot',
          graph_type  =>  'boxes',
          height      =>  $graph_height,
          scale       =>  'right',
#          min_score   =>  $min_score,
#          max_score   =>  $max_score ? $max_score : undef,
          max_hscore   =>  $max_hscore ? $max_hscore : undef,
          score       =>  sub { my $feat = shift; return $feat->score(); },
#           score       =>  sub {
#                       my $feat = shift;
#                       if ($strands) {
#                         $feat->attributes('watson') ? return $feat->attributes('watson') : return 0;
#                       } else {
#                         return $feat->score();
#                       }
#                     },
#          clip        =>  $clip,
          clip        =>  1,
          label       => "window = $bin_width nt",
#           part_color  =>  sub {# see available colors with showrgb
#                   #my $feat = shift;
#                   #my $score = $feat->score();
#                   my $score = shift;
#                   #$score = $feat->attributes('watson') if ($strands);
# 
#                   if ($max_score) {
#                     my $ratio = $score / $max_score;
#                     return (0,0,0) unless ($ratio);# black
#                     return (255,0,0) if ($ratio > 0.9);# red
#                     return (255,165,0) if ($ratio > 0.75);# orange
#                     return (250,128,114) if ($ratio > 0.5);# salmon
#                     return (218,165,32) if ($ratio > 0.25);# goldenrod
#                     return (0,255,0) if ($ratio > 0);# green
#                     return (165,42,42) if ($score > -50);# brown
#                   } else {
#                     return (0,0,0) unless ($score);
#                     return (255,0,0) if ($score > $bin_width * 0.2);# red
#                     return (255,165,0) if ($score > $bin_width * 0.1);# orange
#                     return (255,255,0) if ($score > $bin_width * 0.05);# yellow
#                     return (0,255,0) if ($score > $bin_width * 0.01);# green
#                     return (211,211,211) if ($score > 0);# light gray
#                     return (165,42,42) if ($score > -50);# brown
#                   }
#                 },
#         key => $config->{"$qdfeat" . "_strands"} ? $key_addn . " watson strand" : $key_addn,
          key => $key_addn,
          dual => 0,
          bump  =>  0,
          qdstart =>  $segment->start(),
          qdstop  =>  $segment->stop(),
          features => \@feats,
          ftype  => $type,
      });
      print LOG "add_type($type) finished\n" if ($debug);
      $feature_list->add_feature(
        Bio::Graphics::Feature->new(
          -ref  =>  $ref,
          -start  =>  $segment->start(),
          -stop   =>  $segment->stop(),
          -type   =>  $type,
        ), $type
      );
      
      print LOG "add_feature() for $type finished\n" if ($debug);

} else { # not drawing histogram -- drawing detailed view
#
#
#
#
      print LOG "generating detail display\n" if ($debug);
      print LOG "for detail data, use dsn '", $config->{detail_dsn}, "'\n" if ($debug && $config->{detail_dsn});

      my (%feature_count,$actual_count,$factor,$max) = (0,0,1,0);
      my ($db2,$segment2);
#      $db2 = Bio::DB::GFF->new(
#                  -adaptor  =>  'dbi::mysql',
#                  -dsn      =>  $config->{detail_dsn} ? $config->{detail_dsn} : 'dbi:mysql:database=illumina;host=localhost',
#                  -user     =>  $config->{detail_user} ? $config->{detail_user} : 'anonymous',
#                  -pass     =>  $config->{detail_password} ? $config->{detail_password} : 'password',
#      );
      $self->_db_handle(\$db2,$config);

      $segment2 = $db2->segment(
        -name     =>    $segment->refseq(),
        -start    =>    $segment->start(),
        -stop     =>    $segment->stop(),
      );
      if ($debug) {
	    print LOG "\$db2 isa '", ref($db2), "'\n";
        print LOG "\$segment2 isa '", ref($segment2), "'\n";
        print LOG "\t", $segment2->start(), " - ", $segment2->stop(), "\n";
        print LOG "\tfeature count: ", $segment2->feature_count(), "\n\n";
      }

        my @tracktypes = ();
        if ($qdfeat =~ /!/) {
            for my $feat (split /!/, $qdfeat) {
                print LOG "pushing '$feat' onto \@tracktypes\n" if ($debug);
                $feat =~ s/QD//;
                #push(@tracktypes,"$feat" . ":cufflinks");
                push(@tracktypes,"$feat" . ":QDread");
            }
        
        } else {
            print LOG "pushing '$qdfeat' onto \@tracktypes\n" if ($debug);
            #push(@tracktypes,$qdfeat);
            push(@tracktypes,"$qdfeat:QDread");
        }

      %feature_count = $segment2->types( -enumerate => 1 );

    for my $qdfeat (@tracktypes) {
      print LOG "feature count for '", $segment2->seq_id(), "'\n" if ($debug);
      foreach my $key (keys %feature_count) {
        print LOG "feature: '$key'\n" if ($debug);
        #if (substr($key,0,index($key,':')) eq $qdfeat) {
        if ($key eq $qdfeat) {
          print LOG "\tnumber of '$key' features: '", $feature_count{$key}, "'\n" if ($debug);
          $actual_count += $feature_count{$key};
          if ($actual_count > $config->{max_features}) {
            $factor = int($actual_count/$config->{max_features});
            $factor += 1 if ($factor == 1);
            $max = 1;
          }
          last;
        }
      }
    }

#      print LOG "feature count for '", $segment2->seq_id(), "'\n" if ($debug);
#      foreach my $key (keys %feature_count) {
#        print LOG "feature: '$key'\n" if ($debug);
#        if (substr($key,0,index($key,':')) eq $qdfeat) {
#          print LOG "\tnumber of '$key' features: '", $feature_count{$key}, "'\n" if ($debug);
#          $actual_count = $feature_count{$key};
#          if ($actual_count > $config->{max_features}) {
#            $factor = int($actual_count/$config->{max_features});
#            $factor += 1 if ($factor == 1);
#            $max = 1;
#          }
#          last;
#        }
#      }
      
#    my @tracktypes = ();
#    if ($qdfeat =~ /!/) {
#        for my $feat (split /!/, $qdfeat) {
#            print LOG "pushing '$feat' onto \@tracktypes\n" if ($debug);
#            $feat =~ s/QD//;
#            push(@tracktypes,"$feat" . ":cufflinks");
#        }
#    
#    } else {
#        print LOG "pushing '$qdfeat' onto \@tracktypes\n" if ($debug);
#        push(@tracktypes,$qdfeat);
#    }
    #@tracktypes = qw/ CF-1 /;
      #my $iterator = $segment2->features(-types => "$qdfeat", -iterator => 1);
      #my $iterator = $segment2->features(-types => \@tracktypes, -iterator => 1);
      my $iterator = $segment2->features(-types => \@tracktypes, -iterator => 1);
        print LOG "\$iterator isa '" . ref($iterator) . "'\n" if ($debug);

      my ($feat_cnt,$key_addn,$print_feat) = (0,0,0);
      $actual_count = 0 if ($config->{data_normalized}); # because now we use QDcount to determine "actual" number of features

      while (my $feat = $iterator->next_seq()) {
        ++$feat_cnt;
        print LOG "\$feat_cnt = $feat_cnt\n" if ($debug);  
        #$key_addn = $feat->notes() if ($feat_cnt == 1);
        #$key_addn = $config->{dataset_display_name}->{$qdfeat} || $qdfeat;
        if (!$config->{data_normalized}) {
#          print STDERR "\n\ndata raw\n\n";
          my $fcount = int($feat->attributes('QDcount'));
          if ($fcount && $fcount > 1) {
            --$fcount;
            $actual_count += $fcount;
          }
  
          if ($config->{detail_min_tally} == 1 && $max) {
            # not perfect because we will always skip when $feat_cnt < 2
            next unless ( $feat_cnt % $factor == 0 );
          } elsif ($feat->attributes('QDcount') < $config->{detail_min_tally}) {
            --$feat_cnt;
            $actual_count = $actual_count - $feat->attributes('QDcount');
            next;
          }
        } else {
#          print STDERR "\n\ndata normalized\n\n";
          $actual_count += $feat->attributes('QDcount');
          if ($config->{detail_min_tally} == '0' && $max) {
            # not perfect because we will always skip when $feat_cnt < 2
            next unless ( $feat_cnt % $factor == 0 );
          } elsif ($feat->attributes('QDcount') < $config->{detail_min_tally}) {
            --$feat_cnt;
            $actual_count -= $feat->attributes('QDcount');
            next;
          }
            
        }
        
        ## debugging output
        if ($debug && $print_feat <= 2) {
          print LOG "\n\$feat isa '", ref($feat), "'\n";# should be a Bio::DB::GFF::Feature
          print LOG "\tid: ", $feat->id(), "\n";
          print LOG "\tstart: ", $feat->start(), ", stop: ", $feat->stop(), "\n";
          print LOG "\tgroup name: '", $feat->group()->name(), "'\n";
          print LOG "\tatrribute->QDcount '", $feat->attributes('QDcount'), "'\n";
          my @notes = $feat->get_all_tags();
          foreach my $note (@notes) {
            print LOG "\tattribute->notes() '", $note, "'\n";
          }
          print LOG "display name '", $feat->display_name(), "'\n";
          ++$print_feat;
        }
        ## end of debugging output
        
        my $ftype = $feat->type();
        print LOG "\$ftype isa '", ref($ftype), "'\n" if ($debug);
        my $typestring = $ftype->asString();
        $typestring =~ s/:.+//;
        $type = $typestring;# $type will be used below in add_type() method call
#       $type = 'medip_2';
        $feat->{_max_feature} = 1 if ($max);
        push(@binblahs,$feat);
        #print LOG "max feature count reached\n" if ($debug && $max);
        #last if ($max);
      }
      print LOG "adding type '" . $type . "' to feature_list\n" if ($debug);
      print LOG "max feature count reached\n" if ($debug && $max);
      print LOG "number of features in \@binblahs: ", scalar(@binblahs), "\n" if ($debug);
#     $key_addn = $config->{dataset_display_name}->{$qdfeat} || $qdfeat;
      my $dataset_display_name = $self->_array_to_hash( $config->{dataset_display_name} );
      $key_addn = $dataset_display_name->{$qdfeat} || $qdfeat;
      $actual_count = '0' unless ($actual_count);
      my $units = $config->{data_normalized} ? sprintf("%.2f", $actual_count) . " RPM" : "$actual_count independent reads";
      print LOG "\$config->{detail_feature_color} = '" . ref($config->{detail_feature_color}) . "'\n" if ($debug);
      $feature_list->add_type($type => {
#         key           =>  $max ? "$key_addn" . ": max sequence count (" . $config->{max_features} . ") reached -- $feat_cnt sequences, $actual_count independent reads" : "$key_addn" . ": $feat_cnt sequences, $actual_count independent reads",
#          key           =>  $max ? "$key_addn" . ": max sequence count (" . $config->{max_features} . ") reached -- $feat_cnt sequences, $units" : "$key_addn" . ": $feat_cnt sequences, $units",
          key           =>  $config->{detail_min_tally} ? "$key_addn" . ": Minimum RPK filter (" . $config->{detail_min_tally} . ") -- $feat_cnt sequences, $units" : $max ? "$key_addn" . ": max sequence count (" . $config->{max_features} . ") reached -- $feat_cnt sequences, $units" : "$key_addn" . ": $feat_cnt sequences, $units",
          glyph         => 'generic',
          strand_arrow  => 1,
#         strand        =>  1,
          height        => $config->{detail_proportional} ? \&_height : 4,
          connector     => 0,
#          fgcolor       =>  'green',
#          fgcolor       =>  $config->{detail_feature_color} || 'blue',
	  fgcolor	=>	$config->{detail_feature_color} eq 'by_length' ? sub { my $f = shift; return  $self->_color_by_length($f,$self->_array_to_hash($config->{detail_feature_color_map})); } : $config->{detail_feature_color},
	  bgcolor	=>	$config->{detail_feature_color} eq 'by_length' ? sub { my $f = shift; return  $self->_color_by_length($f,$self->_array_to_hash($config->{detail_feature_color_map})); } : $config->{detail_feature_color},
#          bgcolor       =>  sub { my $f = shift; return 'yellow'; },
#          bgcolor       =>  $config->{detail_feature_color} || 'blue',
#         label         =>  $config->{detail_label} ? \&_label : 0,
          label         =>  1,
          description   =>  $config->{detail_feature_label} || undef,
          bump          =>  '+1',
#        link            =>  "gbrowse_details?name=$qdfeat",
      });

      print LOG "adding features of type '$type' to \@binblahs\n" if ($debug);
      foreach my $feature (@binblahs) {
      
        print LOG "\$feature isa '", ref($feature), "'\n \ 
        start =>  ", $feature->start(), " \
        stop  =>  ", $feature->stop(), " \
        strand  =>  ", $feature->strand(), " \
        source  =>  ", $feature->source(), " \
        seq_id  =>  ", $feature->seq_id()," \
        type    =>  '$type' \
        method  =>  ", $feature->method(), "\n" if (0);
      
        my $graphics_feature = Bio::Graphics::Feature->new(
          -start    =>  $feature->start(),
          -stop     =>  $feature->end(),
          -strand   =>  1,
          -score    =>  $feature->attributes('QDcount'),
#         -source   =>  $feature->source(),
          -ref      =>  $ref,
          -type     =>  $type,
          -name     =>  $config->{detail_label} ? &_label($self,$feature,$segment) : 0,
#          -name     =>  'test',
#         -class    =>  'QuantDisplay',
#         -source   =>  'QuantDisplay.pm',
        );
        
      
#       $feature_list->add_feature($feature=>$type);
        print LOG "adding feature '", ref($graphics_feature), "', type = '", $graphics_feature->primary_tag(), "', to \$feature_list\n" if ($debug);
        $feature_list->add_feature($graphics_feature,$type);
        my $features = $feature_list->features($type);
        print LOG "number of '$type' features = '", scalar(@$features), "'\n" if ($debug);
      }
#     $feature_list->add_feature(\@binblahs,$type);
      print LOG "add_feature finished\n" if ($debug);
    }
  
  }

  close(LOG);
  return $feature_list;

}

sub config_defaults {
  my $self = shift;
  print LOG "config_defaults()\n" if ($debug);

  return { on =>  1 };
}

sub reconfigure {
  # called when a "Configure" button is pressed
  my $self = shift;
  print LOG "reconfigure()\n" if ($debug);
  my $current_config = $self->configuration;

  if ($debug) {
	print LOG "in reconfigure(), current config:\n";
	foreach my $ckey (keys %$current_config) {
		print LOG "config key $ckey = " . $current_config->{$ckey} . "\n";
	}
  }

#  %SITES = map {$SITES{$_} = 0} keys(%SITES);
#  %$current_config = map {$_ => 1} ($self->config_param('QD_display'));
  foreach my $set (keys(%{$current_config->{sites}})) {
	print LOG "setting set '$set' to zero\n" if ($debug);
	$current_config->{$set} = 0;
	$current_config->{$set . "_strands"} = 0;
	$current_config->{"QD_display_order_$set"} = $self->config_param("QD_display_order_$set");
  }
  foreach my $display ($self->config_param('QD_display')) {
    print LOG "setting \$display='$display' to 1\n" if ($debug);
    $current_config->{$display} = 1;
  }
  $self->_display_order();

  foreach my $key ($self->config_param('QD_separate_strands')) {
    $current_config->{$key} = 1;
	print LOG "QD_separate_strands key = '$key'\n" if ($debug);
  }
  
  $current_config->{window} = $self->config_param('QD_window');
  $current_config->{max_detail} = $self->config_param('QD_max_detail');
  $current_config->{on} = $self->config_param('on');
  $current_config->{min_score} = $self->config_param('QD_min_score') || 0;
  #$current_config->{max_score} = $self->config_param('QD_max_score');
  #$current_config->{max_hscore} = $self->config_param('QD_max_score');
  $current_config->{max_hscore} = $self->config_param('QD_max_hscore');
  #$current_config->{max_hscore} = 1000;
  $current_config->{graph_height} = $self->config_param('QD_graph_height');
  #$current_config->{clip} = $self->config_param('QD_clip') || 0;
  $current_config->{clip} = $self->config_param('QD_clip') || 1;
  $current_config->{detail_label} = $self->config_param('QD_detail_label');
  $current_config->{detail_proportional} = $self->config_param('QD_detail_proportional');
  $current_config->{detail_min_tally} = $self->config_param('QD_detail_min_tally') || 0;
  
  if ($debug) {
	print LOG "\n\ncurrent config (final time):\n";
	foreach my $ckey (keys %$current_config) {
		print LOG "$ckey = " . $current_config->{$ckey} . "\n";
	}
  }
}

sub configure_form {
  my $self = shift;
# generate the inline configure form
  print LOG "configure_form()\n" if ($debug);
  my $current_config = $self->configuration;
  #$self->_configure_browser($current_config);
  #$self->configure_sites($current_config);
  $self->configure_sites();

  if ($debug) {
    print LOG "in configure_form(), current configuration:\n";
    print LOG "\$self isa '", ref($self), "'\n";
    print LOG "\$current_config isa '", ref($current_config), "'[$current_config]\n";
    foreach my $key (keys %$current_config) {
    print LOG "\$key = '$key'\t";
    if ($current_config->{$key}) {
        print LOG "-> ", $current_config->{$key}, "\n";
    } else {
      print LOG "has no setting\n";
    }
  }
  }
  
  my $datapanelrows;
  if ($debug) {
    print LOG "cofnigure_form: \%SITES contains:\n";
    while (my($key,$value) = each %SITES) {
      print LOG "'$key' => '$value'\n"; 
    }
  }
  print LOG "building data panel rows\n" if ($debug); 

  foreach my $dataname (sort { $SITES{$a} <=> $SITES{$b} } keys %SITES) {
    $datapanelrows .= TR({-class => 'searchbody'},
                        td(checkbox(-name     =>  $self->config_name('QD_display'),
                                    -checked  =>  $current_config->{$dataname} ? 'checked' : 0,
#                                   -label    =>  $current_config->{dataset_display_name}->{$dataname} || $dataname,
                                    -label    =>  $self->_array_to_hash($current_config->{dataset_display_name})->{$dataname} || $dataname,
                                    -value    =>  $dataname
                                    )),
                        td({align => 'center'}, checkbox(
                                    -name     =>  $self->config_name("QD_separate_strands"),
                                    -checked  =>  $current_config->{$dataname . "_strands"} ? 'checked' : 0,
                                    -label    =>  '',
                                    -value    =>  "$dataname" . "_strands")
                                    ),
                        td(popup_menu(
                                      -name   =>  $self->config_name("QD_display_order_$dataname"),
                                      -values =>  [1 .. scalar(keys %SITES)],
                                      -default  =>  $SITES{$dataname},
                                      )
                          ),
                      );
  }


  print LOG "building windows radio buttons\n" if ($debug);
  my @windows = radio_group(
                                -name   =>  $self->config_name('QD_window'),
                                -values => ['Dynamic', sort { $a <=> $b } @BINS],
                                -cols   =>  4,
                                -default => $current_config->{'window'} || 'Dynamic',
                                );

  if ($current_config->{'max_detail_window'} && $current_config->{'max_detail_window'} > $BINS[0]) {
    push(@BINS, $current_config->{'max_detail_window'});
  }

  print LOG "building detail_windows radio buttons\n" if ($debug);
  my @detail_windows = radio_group(
                                -name   =>  $self->config_name('QD_max_detail'),
                                -values => [sort { $a <=> $b } (@BINS, '0')],
                                -labels =>  {0  =>  'never'},
                                -cols   =>  4,
                                -default => $current_config->{'max_detail'} || '0',
                                );

  print LOG "building min_tally radio buttons\n" if ($debug);
  my @min_tally = radio_group(
                                -name   =>  $self->config_name('QD_detail_min_tally'),
#                                -values => [sort { $a <=> $b } (1,2,5,10,20,50,75,100)],
                                -values => [sort { $a <=> $b } ('0',0.10,0.25,0.50,1.0,2.5,5,10,20,50,100)],
                                -cols   =>  4,
                                -default => $current_config->{'detail_min_tally'} || '0',
                                -labels =>  { '0' => 'zero' },
                                );


#  my @min_scores = radio_group(
#                                -name     =>  $self->config_name('QD_min_score'),
#                                -values   =>  [-1000,-500,-100,-50,0,50,100,500,1000],
#                                -cols     =>  4,
#                                -default  =>  $current_config->{'min_score'} || '0',
#                              );

  print LOG "building detail_label radio buttons\n" if ($debug);
  my @detail_label = radio_group(
                                -name     =>  $self->config_name('QD_detail_label'),
                                -values   =>  [0,1],
                                -labels   =>  {0 => 'no', 1 => 'yes'},
                                -default  =>  $current_config->{'detail_label'} || '0',
                              );

  print LOG "building detail_proportional radio buttons\n" if ($debug);
  my @detail_proportional = radio_group(
                                -name     =>  $self->config_name('QD_detail_proportional'),
                                -values   =>  [0,1],
                                -labels   =>  {0 => 'no', 1 => 'yes'},
                                -default  =>  $current_config->{'detail_proportional'} || '0',
                              );

  print LOG "builing max_scores\n" if ($debug);
  my $max_hscores = {
                      1         =>  1,
                      5         =>  5,
                      10        =>  10,
                      25        =>  25,
                      50        =>  50,
                      75        =>  75,
                      100       =>  100,
                      300       =>  300,
                      500       =>  500,
                      800       =>  800,
                      1000      =>  '1,000',
                      3000      =>  '3,000',
                      5000      =>  '5,000',
                      8000      =>  '8,000',
                      10000   =>  '10,000',
                      30000   =>  '30,000',
                      50000   =>  '50,000',
                      80000   =>  '80,000',
                      100000    =>  '100,000',
                      300000    =>  '300,000',
                      500000    =>  '500,000',
                      800000    =>  '800,000',
                      1000000 =>  '1,000,000',
                      0     =>  'Dynamic',
                    };

  print LOG "building max_scores radio buttons\n" if ($debug);
  my @max_scores = radio_group(
                                -name     =>  $self->config_name('QD_max_hscore'),
                                -values   =>  [0,1,5,10,25,50,75,100,300, 500,800,1000,3000,5000,8000,10000,30000,50000,80000,100000,300000,500000,800000,1000000],
                                -labels   =>  $max_hscores,
                                -cols     =>  4,
                                -default  =>  $current_config->{'max_hscore'} || '0',
                              );

  print LOG "building graph_heights radio buttons\n" if ($debug);
  my @graph_heights = radio_group(
                                -name     =>  $self->config_name('QD_graph_height'),
                                -values   =>  [10,25,50,75,100,125,150,175,250,500],
                                -cols     =>  5,
                                -default  =>  $current_config->{'graph_height'} || 125,
                              );

  print LOG "building form\n" if ($debug);
  my $form;
  my $readme = $current_config->{help_file_url};
  $form = table(
      TR({-class=>'searchtitle'},
      th("QuantDisplay Configuration Options (<a href=\"$readme\" target=\"_QuantDisplay_README\">README</a>)")),
      TR({-class=>'searchbody'},
        th({-align=>'LEFT'},
         "QuantDisplay",
         radio_group(-name=>$self->config_name('on'),
          -values  =>[0,1],
          -labels  => {0=>'off',1=>'on'},
          -default => $current_config->{on},
          -override=>1,
          )
        )
      ),
      TR({-class => 'searchbody'}, td(p({-style => "padding: 0; margin: 0; border: 0;"},"Note that you must also select at least one <span style=\"font-weight: bold;\">Data Panel</span>, below. For help, see the <a href=\"$readme\" target=\"_QuantDisplay_README\">README</a> file."))),
      TR({-class => 'searchbody'}, td('&nbsp;')),
    );
#       TR({-class => 'searchbody'}, td('&nbsp;')),
#       TR({-class => 'searchtitle'}, th({-align => 'left'},'Sets of data to display')),
#       TR({-class=>'searchbody'}, td(@buttons)),
#       TR({-class => 'searchbody'}, td('&nbsp;')));

  $form .= table(
#      TR({-class => 'searchbody'}, td('&nbsp;')),
      #TR({-class => 'searchtitle'}, th({-align => 'left', -width => '400px'}, 'Data Panels'), th({-align => 'center', -width => '100px'}, 'Separate Strands<br>(in histogram)'), th({-align => 'left'}, 'Relative Panel Position')),
      TR({-class => 'searchtitle'}, th({-align => 'left', -width => '500px'}, 'Data Panels'), th({-align => 'center', -width => '100px'}, 'Separate Strands<br>(in histogram)'), th({-align => 'left'}, 'Relative Panel Position')),
      $datapanelrows,
      TR({-class => 'searchbody'}, td('&nbsp'), td('&nbsp'), td('&nbsp')));


      
  $form .= table(
    TR({-class => 'searchtitle'}, th('Histogram View Formatting Options')),   TR({-class => 'searchtitle'}, th({-align => 'left'},"Rolling Window Size")),
    TR({-class => 'searchbody'}, td(@windows)),
    TR({-class => 'searchbody'}, td('&nbsp;')),

#   TR({-class => 'searchtitle'}, th({align => 'left'}, 'Minimum value for histogram')),
#   TR({-class => 'searchbody'}, td({align => 'left'}, @min_scores)),
#   TR({-class => 'searchbody'}, td('&nbsp;')),

    TR({-class => 'searchtitle'}, th({align => 'left'}, 'Maximum value for histogram')),
    TR({-class => 'searchbody'}, td({align => 'left'}, @max_scores)),
    TR({-class => 'searchbody'}, td('&nbsp;')),

    TR({-class => 'searchtitle'}, th({align => 'left'}, 'Height of graph (in pixels)')),
    TR({-class => 'searchbody'}, td({align => 'left'}, @graph_heights)),
    TR({-class => 'searchbody'}, td('&nbsp;')),

#      th({-align=>'LEFT', -class => 'searchtitle'},
#          "Clip values beyond max and min? ",
#          radio_group(
#           -name=>$self->config_name('QD_clip'),
#           -values  =>[0,1],
#           -labels  => {0=>'no',1=>'yes'},
#           -default => $current_config->{clip} || '0',
#         )
#       )
  );

  unless ($current_config->{no_detail}) {
    $form .= table(
      TR({-class => 'searchbody'}, td('&nbsp;')),
      TR({-class => 'searchtitle'}, th('Detailed View Formatting Options')),
      TR({-class => 'searchtitle'}, th({-align => 'left'},"Maximum Segment Size to Display Detailed View")),
      TR({-class => 'searchbody'}, td(@detail_windows)),
      TR({-class => 'searchbody'}, td('&nbsp;')),
       TR({-class => 'searchtitle'}, th({-align => 'left'},"Minimum RPM Value to Display Reads in Detailed View")),
      TR({-class => 'searchbody'}, td(@min_tally)),
      TR({-class => 'searchbody'}, td('&nbsp;')),
     TR({-class => 'searchtitle'}, th({align => 'left'}, 'Display labels')),
      TR({-class => 'searchbody'}, td({align => 'left', style=> "padding-left: 10px;"}, @detail_label)),
      TR({-class => 'searchbody'}, td('&nbsp;')),
  
      TR({-class => 'searchtitle'}, th({align => 'left'}, 'Display proportional features')),
      TR({-class => 'searchbody'}, td({align => 'left', style => "padding-left: 10px;"}, @detail_proportional)),
      TR({-class => 'searchbody'}, td('&nbsp;')),
  
  
    );
  }
  #print LOG "returning from configure_form():\n $form\n" if ($debug);
#  return "<h2>hello world!</h2>";
  return $form;
}

sub configure_sites {
  my $self = shift;
  my $config = shift;
  print LOG "configure_sites()\n" if ($debug);
  my $db = $self->QDdatabase;
  $config = $self->configuration unless ($config);
  my @types = ();
  print LOG "\$self isa '", ref($self), "'\n\$db isa '", ref($db), "'\n" if ($debug);
  if (!ref($db)) {
  #if (defined($config->{sites})) {
	my $sites = $config->{sites};
	if ($debug) {
		print LOG "\$sites isa '", ref($sites), "'\n";
		foreach my $e (keys %$sites) {
            #$sites->{$e} = 1;
			print LOG "site key: '$e', value: ", $sites->{$e}, "\n";
		}
	}
  	%SITES = %$sites;
	#$self->_display_order();
	#@SITES = @$sites; # I don't think @SITES is ever used for anything
  } else {
  	@types = $db->types();
  

	my $pos = 0;
	foreach my $type (@types) {
	  my $method = $type->method();
	  #if ($method =~ /QD(\w+)_\d+/ && !$SITES{$1}) {
	  if ($method =~ /QD([.-\w]+)_\d+/ && !$SITES{$1}) {
	    #$SITES{$1} = $method;
	    $SITES{$1} = ++$pos;
	  } elsif ($method =~ /QD([.-\w!][^_]+)$/ && !$SITES{$1}) {
        $SITES{$1} = ++$pos;
      }
	}
	#$config->{sites} = \@SITES;
	#@SITES = keys(%SITES);# I don't think @SITES is ever used for anything
  }
  $self->_display_order();
#  $config->{sites} = \@SITES;
  $config->{sites} = \%SITES;
}

sub _configure_browser {
  my $self = shift;
  my $config = shift;
  print LOG "_configure_browser()\n" if ($debug);
  my $bc = $self->browser_config();
  print LOG "\$self isa '", ref($self), "'\n" if ($debug);
  print LOG "\$bc isa '", ref($bc), "'\n" if ($debug);
  
  $config->{max_features} = $bc->plugin_setting('max_features') || 250;
  $config->{default_features} = $bc->plugin_setting('default_features') || '';
  $config->{detail_feature_color} = $bc->plugin_setting('detail_feature_color');
  $config->{detail_feature_color_map} = $self->_detail_feature_color_map($bc->plugin_setting('detail_feature_color_map'));
  $config->{content_description} = $bc->plugin_setting('content_description') || '';
  $config->{detail_dsn} = $bc->plugin_setting('detail_dsn') || undef;
  $config->{detail_user} = $bc->plugin_setting('detail_user');
  $config->{detail_password} = $bc->plugin_setting('detail_password');
  $config->{data_name} = $bc->plugin_setting('data_name') || 'QuantDisplay';
  $config->{no_detail} = $bc->plugin_setting('no_detail') || 0;
  $config->{detail_feature_label} = $bc->plugin_setting('detail_feature_label') || 0;
  $config->{QD_datasource} = $self->_QD_datasource($bc->plugin_setting('datasource'));
  $config->{dataset_display_name} = $self->_dataset_display_name($bc->plugin_setting('dataset_display_name'));
  $config->{help_file_url} = $bc->plugin_setting('help_file_url') || 'index.html';
  $config->{data_normalized} = $bc->plugin_setting('data_normalized');
  $config->{max_detail_window} = $bc->plugin_setting('max_detail_window');
  #return $bc;
  #return 1;
  return $config;
}

sub _detail_feature_color_map {
	my $self = shift;
	my $text = shift;
	my $hashref = $self->_config_array($text);
	return $hashref
}

sub _color_by_length {
	my $self = shift;
	my $f = shift;
	my $colormap = shift;
	my $length = $f->length();
	#print STDERR "_color_by_length()\n" if ($debug);
	#print STDERR "\n\$f isa '" . ref($f) . "'\n\$colormap isa '" . ref($colormap) . "'\nlength = '$length'\n" if ($debug);
	#print STDERR "\n\$f isa '" . ref($f) . "'\n\$colormap is '$colormap'\nlength = '$length'\n" if ($debug);
	my $color = 'peachpuff';

	foreach my $threshold (sort {$a <=> $b } keys %$colormap) {
	#	print STDERR "$length < $threshold?\n" if ($debug);
		if ($length <= $threshold) {
			$color = $colormap->{$threshold};
			last;
		}
	}
	#print STDERR "returning color '$color' from _color_by_length()\n" if ($debug);
	return $color;
}

sub _height {
  my $feature = shift;

#  if ($debug) {
#    open(TMP,">>/tmp/QD_height.log");
#    print TMP "QuantDisplay::_height() called\n";
#    print TMP "\$feature isa '", ref($feature), "'\n";
#  }
# $feature isa Bio::DB::GFF::Feature
# $feature isa Bio::Graphics::Feature as of gbrowse 1.69

  my $count = $feature->attributes('QDcount') || $feature->score();
  $count = 1 unless ($count);
  my $normalized = 0;
  $normalized = 1 if (int($count)/$count != 1);# a hack, but it works most of the time

  print TMP "\$count = $count\n" if ($debug);
  close(TMP) if ($debug);

  if (!$normalized) {
    if ($count <= 5) {
      return 4;
    } elsif ($count <= 10) {
      return 8;
    } elsif ($count <= 20) {
      return 14;
    } elsif ($count <= 40) {
      return 20;
    } elsif ($count <= 60) {
      return 26;
    } elsif ($count <= 80) {
      return 32;
    } elsif ($count <= 100) {
      return 38 
    } else {
      return 50;
    }
  } else {
    if ($count <= 0.1) {
      return 4;
    } elsif ($count <= 0.25) {
      return 8;
    } elsif ($count <= 0.5) {
      return 10;
    } elsif ($count <= 0.75) {
      return 12;
    } elsif($count <= 1) {
      return 14;
    } elsif ($count <= 2.5) {
      return 16;
    } elsif ($count <= 5) {
      return 18;
    } elsif ($count <= 10) {
      return 20;
    } elsif ($count <= 20) {
      return 22;
    } else {
      return 24;
    }
  }

}

sub _label {
  my $obj = shift;
  my $feature = shift;
  my $segment = shift;
  my $label = '';
  my $config  = $obj->configuration();
  
  if ($debug) {
    open(LBL,">/tmp/QD_label.log");
    print LBL "QuantDisplay::_label() called\n";
    print LBL "\$feature isa '", ref($feature), "'\n";
  }
  
  if (0) {## in future, include option to show / not show DNA sequence of feature in its label
    my $featseq = $segment->subseq($feature->start(),$feature->stop());
    $label = $featseq->seq()->seq() || ' '; # note that if DNA sequences have not been loaded into DB, then this will be empty
    if ($debug) {
      print LBL "\$segment [$segment] isa '", ref($segment), "'\n\$featseq [$featseq] isa '", ref($featseq), "'\n\$label [$label] isa '", ref($label), "'\n";
      print LBL "abs_start = ", $segment->abs_start(), ", abs_end = ", $segment->abs_end(), "\n";
      print LBL "feature start = ", $feature->start(), ", feature end = ", $feature->end(), "\n";
    }
  }

  my $count = $config->{data_normalized} ? sprintf("%.2f", $feature->attributes('QDcount')) : $feature->attributes('QDcount');
  my $refmol = $feature->location()->seq_id();
  my $start = $feature->start();
  my $stop = $feature->end();
  my $max_label_length = 60;# I need to trim long labels or this routine fails when there are lots of features

  #$label .= $config->{data_normalized} ? " $count RPM" : " $count X";
  $label = "$refmol" . ":$start-$stop";
#  my $rpm = $config->{data_normalized} ? " $count RPM" : " $count X" . $label;
  my $rpm = $config->{data_normalized} ? " $count RPM" : " $count ";
  $label = $rpm . " " . $label;
  foreach my $tag ($feature->get_all_tags()) {
    next if ($tag eq 'QDcount' || $tag eq 'Note');
    last if (length($label) > $max_label_length);
    my $tagstring = join(' ', $feature->get_tag_values($tag));
  }
  $label = length($label) > $max_label_length ? substr($label,0,$max_label_length) . " ... " : $label;

  if ($debug) {
    print LBL "returning $label\n";
    close(LBL);
  }

  return $label;
}

sub _display_order {
  my $self = shift;
  my $configuration = $self->configuration();
  print LOG "_display_order()\n" if ($debug);
    
  foreach my $site (keys %SITES) {
    $SITES{$site} = $configuration->{"QD_display_order_$site"};
  }
  
}

sub _QD_datasource {
  my $self = shift;
  my $source_txt = shift;

  return $self->_config_array($source_txt);

}

sub _dataset_display_name {
  my $self = shift;
  my $source_txt = shift;
# print LOG "_dataset_display_name()\nsource text = '$source_txt'\n" if ($debug && $source_txt);
  
# return $self->_config_hash($source_txt);
  return $self->_config_array($source_txt);
}

sub _config_hash {
  my $self = shift;
  my $source_txt = shift;
  print LOG "_config_hash($source_txt)\n" if ($debug && $source_txt);
  my %hash = ();
  return \%hash unless ($source_txt);
  print LOG "converting text into hash\n" if ($debug);  
  if ($source_txt =~ /\{(.+)\}/m) {
    my $sources = $1;
#   print LOG "\$sources = '$sources'\n" if ($debug);
    foreach my $line (split /,/, $sources) {
      if ($line =~ /(.+)\=>(.+)/) {
        my ($key,$value) = ($1,$2);
        $key =~ s/\s//g;
        $value =~ s/[\s\n]//;
        if ($debug) {
          print LOG "\t\$key = '$key'\n\t\$value = '$value'\n";
        }
        $hash{$key} = $value;
      }
    }
  }
  return \%hash;

}

sub _config_array {
  my $self = shift;
  my $source_txt = shift;
  print LOG "_config_array($source_txt)\n" if ($debug && $source_txt);
  my @array = ();
  return \@array unless ($source_txt);
  print LOG "converting text into array\n" if ($debug); 
  if ($source_txt =~ /\{(.+)\}/m) {
    my $sources = $1;
#   print LOG "\$sources = '$sources'\n" if ($debug);
    foreach my $line (split /,/, $sources) {
      if ($line =~ /(.+)\=>\s*(.+)/) {
        my ($val1,$val2) = ($1,$2);
        $val1 =~ s/\s//g;
#       $val2 =~ s/[\s\n]//;
        $val2 =~ s/[\n]//g;
        if ($debug) {
          print LOG "\t\$val1 = '$val1'\n\t\$val2 = '$val2'\n";
        }
#       $hash{$key} = $value;
        push(@array,$val1,$val2);
      }
    }
  }
  print LOG "returning array reference from _config_array()\n" if ($debug);
  return \@array;

}

sub _array_to_hash {
  my $self = shift;
  my $arrayref = shift;
  return unless(ref($arrayref));
  my %hash = ();
  my @array = @$arrayref;
  %hash = @array;
  return \%hash;
}



sub _score {
      my $feat = shift;
      my $passed_object = $_[$#_];
      my $strand = $passed_object->{_strand};
#     my $strand = 'watson';
      $feat->{_strand} = $strand;
      if ($debug) {
        open(LOG2, ">/tmp/score.log") or die "can't open log file: $!";
        print LOG2 "sub _score()\n";
        print LOG2 "\$feat isa '", ref($feat), "'\n";
        print LOG2 "should be '", scalar(@_), "' arguments\n";
        foreach my $arg (@_) {
          print LOG2 "arg: '", ref($arg), "', '$arg'\n";
        }
        print LOG2 "strand = '$strand'\n";
        print LOG2 "\$passed_object isa '", ref($passed_object), "' ($passed_object)\n";
        foreach my $key (keys %$passed_object) {
          print LOG2 "key: '$key', value: '", $passed_object->{$key}, "'\n";
        }
        close(LOG2);
      }

      if ($feat->{_strand} eq 'watson') {
        return $feat->attributes('watson');
      } elsif ($feat->{_strand} eq 'crick') {
        return 1 - $feat->attributes('crick');
      } else {
#                                 return $feat->score();
        return 666;
      }
}

sub _db_handle {
        my $self = shift;
        my $dbr = shift;
        my $config = shift;
        $config = $self->configuration unless ($config);
        $self->_configure_browser($config);
        $$dbr = Bio::DB::GFF->new(
                    -adaptor  =>  'dbi::mysql',
                    -dsn      =>  $config->{detail_dsn} ? $config->{detail_dsn} : 'dbi:mysql:database=illumina;host=localhost',
                    -user     =>  $config->{detail_user} ? $config->{detail_user} : 'anonymous',
                    -pass     =>  $config->{detail_password} ? $config->{detail_password} : 'password',
        );
#        $config->{QDdatabase} = $$dbr; # don't do this!, it doesn't work and creates a Storable error
                                        # either when storing a reference or dereferenced reference to config.
        return 1;
}

sub QDdatabase {
    my $self = shift;
    my $config = shift;
    my $dbr;
    unless (defined($config->{QDdatabase})) { # at this point, this will never eval to true
       $self->_db_handle(\$dbr);
    } else {
        #$dbr = $$config->{QDdatabase};# don't do this, it breaks Storable
    }
    return $dbr;
}

1;
