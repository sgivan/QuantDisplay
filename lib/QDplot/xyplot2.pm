package Bio::Graphics::Glyph::xyplot2;
# $Id: xyplot2.pm,v 1.4 2008/11/06 00:17:36 givans Exp $
#
#     xyplot2 -- subclass some methods from xyplot to generate better graphs
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
#use GD 'gdTinyFont';

use Bio::Graphics::Glyph::xyplot;
#use base qw(Bio::Graphics::Glyph::minmax);
use vars qw/ @ISA /;
#use constant DEFAULT_POINT_RADIUS=>4;
#our $VERSION = 1.5;
our $VERSION = '$Revision: 1.4 $';
@ISA = qw/ Bio::Graphics::Glyph::xyplot /;

my %SYMBOLS = (
	       triangle => \&draw_triangle,
	       square   => \&draw_square,
	       disc     => \&draw_disc,
	       point    => \&draw_point,
	      );
my $debug = 0;
if ($debug) {
	open(LOG,">/tmp/xyplot2.log") or warn("can't open xplot2.log: $!");
	print LOG "+" x 50 . "\n_xyplot2()\n\n";
}

# Default pad_left is recursive through all parts. We certainly
# don't want to do this for all parts in the graph.
# sub pad_left {
#   my $self = shift;
#   return 0 unless $self->level == 0;
#   return $self->SUPER::pad_left(@_);
# }
# 
# # Default pad_left is recursive through all parts. We certainly
# # don't want to do this for all parts in the graph.
# sub pad_right {
#   my $self = shift;
#   return 0 unless $self->level == 0;
#   return $self->SUPER::pad_right(@_);
# }
# 
# sub point_radius {
#   shift->option('point_radius') || DEFAULT_POINT_RADIUS;
# }
# 
# sub pad_top {
#   my $self = shift;
#   my $pad = $self->Bio::Graphics::Glyph::generic::pad_top(@_);
#   if ($pad < ($self->font('gdTinyFont')->height+2)) {
#     $pad = $self->font('gdTinyFont')->height+2;  # extra room for the scale
#   }
#   $pad;
# }
# 
# sub pad_bottom {
#   my $self = shift;
#   my $pad  = $self->Bio::Graphics::Glyph::generic::pad_bottom(@_);
#   if ($pad < ($self->font('gdTinyFont')->height)/4) {
#     $pad = ($self->font('gdTinyFont')->height)/4;  # extra room for the scale
#   }
#   $pad;
# }
# 
sub scalecolor {
   my $self = shift;
   my $color = $self->color('scale_color') || $self->fgcolor;
}
# 
# sub default_scale
# {
#   return 'right';
# }
# 
sub draw {
  my $self = shift;
  my ($gd,$dx,$dy) = @_;
  print LOG "\ndraw()\n" if ($debug);
  my ($left,$top,$right,$bottom) = $self->calculate_boundaries($dx,$dy);
  my @parts = $self->parts;
	my $force_zero = $self->{factory}->{options}->{force_zero};

  return $self->SUPER::draw(@_) unless @parts > 0;

  my ($min_score,$max_score) = $self->minmax(\@parts);
	if ($force_zero) {
		print LOG "forcing origin at zero\n" if ($debug);
	}
# 	print LOG "min_score = $min_score\nmax_score = $max_score\n";
# 	print LOG "top = $top\nbottom = $bottom\n" if ($debug);

  my $side = $self->_determine_side();

  # if a scale is called for, then we adjust the max and min to be even
  # multiples of a power of 10.
  if ($side) {
    $max_score = max10($max_score);
    $min_score = min10($min_score);
  }

  my $height = $self->height;
  my $scale  = $max_score > $min_score ? $height/($max_score-$min_score)
                                       : 1;
#	my $x = $left;
#	my $y = $top + $self->pad_top;

  # position of "0" on the scale
  if ($debug) {
  	my ($gdwidth,$gdheight) = $gd->getBounds();
  	print LOG "gd height = $gdheight, gd width = $gdwidth\n";
  	print LOG "dx = $dx, dy = $dy\nleft = $left, right = $right\n";
  	print LOG "top = $top, bottom = $bottom\n";
  	print LOG "height = $height, scale = $scale\n";
#		print LOG "x = $x, y = $y\n";
		print LOG "min_score = $min_score\nmax_score = $max_score\n";
	}
	
	my $y_origin;
  $y_origin = $min_score <= 0 ? $bottom - (0 - $min_score) * $scale : $bottom;
 	if ($force_zero) {
#			$y_origin = $top + (($bottom - $top)/2);
# 		my $tdiff = abs($max_score - 0) != 0 ? abs($max_score - 0) : $max_score;
# 		print LOG "tdiff = $tdiff\n" if ($debug);
# 		$y_origin = $tdiff * $scale + $top;
 	}
  $y_origin    = $top if $max_score < 0;

	print LOG "draw() y_origin = $y_origin\n" if ($debug);
	$self->{_y_origin} = $y_origin;

  my $clip_ok = $self->option('clip');
  $self->{_clip_ok}   = $clip_ok;
  $self->{_scale}     = $scale;
  $self->{_min_score} = $min_score;
  $self->{_max_score} = $max_score;
  $self->{_top}       = $top;
  $self->{_bottom}    = $bottom;

  # now seed all the parts with the information they need to draw their positions
  foreach (@parts) {
    my $s = $_->score;
    next unless defined $s;
    $_->{_y_position}   = $self->score2position($s);
    print LOG "for part with score = $s, _y_position = ", $_->{_y_position}, "\n" if ($debug);
  }
  my $type           = $self->option('graph_type') || $self->option('graphtype') || 'boxes';
  my (@draw_methods) = $self->lookup_draw_method($type);
  $self->throw("Invalid graph type '$type'") unless @draw_methods;

#$self->_draw_scale($gd,$scale,$min_score,$max_score,$dx,$dy,$y_origin);

  for my $draw_method (@draw_methods) {
  	print LOG "calling $draw_method" . "()\n" if ($debug);
    $self->$draw_method($gd,$dx,$dy,$y_origin,$force_zero);
  }
 $self->_draw_scale($gd,$scale,$min_score,$max_score,$dx,$dy,$y_origin,$force_zero);

  $self->draw_label(@_)       if $self->option('label');
  $self->draw_description(@_) if $self->option('description');
}
# 
# sub lookup_draw_method {
#   my $self = shift;
#   my $type = shift;
# 
#   return '_draw_histogram'            if $type eq 'histogram';
#   return '_draw_boxes'                if $type eq 'boxes';
#   return qw(_draw_line _draw_points)  if $type eq 'linepoints';
#   return '_draw_line'                 if $type eq 'line';
#   return '_draw_points'               if $type eq 'points';
#   return;
# }
# 
# sub score {
#   my $self    = shift;
#   my $s       = $self->option('score');
#   return $s   if defined $s;
#   return eval { $self->feature->score };
# }
# 
# sub score2position {
#   my $self  = shift;
#   my $score = shift;
# 
#   return unless defined $score;
# 
#   if ($self->{_clip_ok} && $score < $self->{_min_score}) {
#     return $self->{_bottom};
#   }
# 
#   elsif ($self->{_clip_ok} && $score > $self->{_max_score}) {
#     return $self->{_top};
#   }
# 
#   else {
# #  	if ($score > 0) {
# #    	my $position      = ($score-$self->{_min_score}) * $self->{_scale};
# #    	return $self->{_bottom} - $position - $self->pad_top - $self->pad_bottom;
# 			my $position      = ($score-$self->{_min_score}) * $self->{_scale};
# 			return $self->{_bottom} - $position;
# #		}
#   }
# }

sub log10 { log(shift)/log(10) }
sub max10 {
  my $a = shift;
  return 0 if $a==0;
  return -min10(-$a) if $a<0;
  return max10($a*10)/10 if $a < 1;
  
  my $l=int(log10($a));
  $l = 10**$l; 
  my $r = $a/$l;
  return $r*$l if int($r) == $r;
  return $l*int(($a+$l)/$l);
}
sub min10 {
  my $a = shift;
  return 0 if $a==0;
  return -max10(-$a) if $a<0;
  return min10($a*10)/10 if $a < 1;
  
  my $l=int(log10($a));
  $l = 10**$l; 
  my $r = $a/$l; 
  return $r*$l if int($r) == $r;
  return $l*int($a/$l);
}

# sub _draw_histogram {
#   my $self = shift;
#   my ($gd,$left,$top,$bottom) = @_;
# 
#   my @parts  = $self->parts;
#   my $fgcolor = $self->fgcolor;
# 
#   # draw each of the component lines of the histogram surface
#   for (my $i = 0; $i < @parts; $i++) {
#     my $part = $parts[$i];
#     my $next = $parts[$i+1];
#     my ($x1,$y1,$x2,$y2) = $part->calculate_boundaries($left,$top);
#     $gd->line($x1,$part->{_y_position},$x2,$part->{_y_position},$fgcolor);
#     next unless $next;
#     my ($x3,$y3,$x4,$y4) = $next->calculate_boundaries($left,$top);
#     if ($x2 == $x3) {# connect vertically to next level
#       $gd->line($x2,$part->{_y_position},$x2,$next->{_y_position},$fgcolor); 
#     } else {
#       $gd->line($x2,$part->{_y_position},$x2,$bottom,$fgcolor); # to bottom
#       $gd->line($x2,$bottom,$x3,$bottom,$fgcolor);                        # to right
#       $gd->line($x3,$bottom,$x3,$next->{_y_position},$fgcolor);   # up
#     }
#   }
# 
#   # end points: from bottom to first
#   my ($x1,$y1,$x2,$y2) = $parts[0]->calculate_boundaries($left,$top);
#   $gd->line($x1,$bottom,$x1,$parts[0]->{_y_position},$fgcolor);
#   # from last to bottom
#   my ($x3,$y3,$x4,$y4) = $parts[-1]->calculate_boundaries($left,$top);
#   $gd->line($x4,$parts[-1]->{_y_position},$x4,$bottom,$fgcolor);
# 
#   # That's it.  Not too hard.
# }

sub _draw_boxes {
  my $self = shift;
  my ($gd,$left,$top,$y_origin) = @_;
	print LOG "\n_draw_boxes()\n" if ($debug);
	
  my @parts    = $self->parts;
  my $fgcolor  = $self->fgcolor;
  my $bgcolor  = $self->bgcolor;
  my $lw       = $self->linewidth;
  my $negative = $self->color('neg_color') || $bgcolor;
  my $height   = $self->height;

  my $partcolor = $self->code_option('part_color');
  my $factory  = $self->factory;

  # draw each of the component lines of the histogram surface
  for (my $i = 0; $i < @parts; $i++) {
		print LOG "\npart $i\n" if ($debug);
    my $part = $parts[$i];
    my $next = $parts[$i+1];

    my ($color,$negcolor);

    # special check here for the part_color being defined so as not to introduce lots of
    # checking overhead when it isn't
    if ($partcolor) {
      $color    = $factory->translate_color($factory->option($part,'part_color',0,0));
      $negcolor = $color;
    } else {
      $color    = $bgcolor;
      $negcolor = $negative;
    }

		if ($debug) {
			print LOG "part score = ", $part->score(), "\n";
			print LOG "part->{left} = ", $part->{left}, "\n";
			print LOG "top = $top\n";
			print LOG "part->{top} = ", $part->{top}, "\n";
			print LOG "part->pad_top = ", $part->pad_top, "\n";
			print LOG "part->{_y_position} = ", $part->{_y_position}, "\n";
			print LOG "part->pad_bottom = ", $part->pad_bottom, "\n";
		}

    my ($x1,$y1,$x2,$y2) = $part->calculate_boundaries($left,$top);
    if ($debug) {
    	print LOG "called calculate_boundaries($left,$top) to obtain x1, y1, x2, y2\n";
    	print LOG "x1 = $x1, y1 = $y1\nx2 = $x2, y2 = $y2\n";
    	print LOG "calling filled_box()\n";
		}
    if ($part->{_y_position} < $y_origin) {
      $self->filled_box($gd,$x1,$part->{_y_position},$x2,$y_origin,$color,$fgcolor,$lw);
#			$self->filled_box($gd,$x1,$part->{_y_position}-15,$x2,$y_origin-9,$color,$fgcolor,$lw);
    } else {
      $self->filled_box($gd,$x1,$y_origin,$x2,$part->{_y_position},$negcolor,$fgcolor,$lw);
#				$self->filled_box($gd,$x1,$y_origin,$x2,$y_origin + (abs($part->score) * $self->{_scale}),$negcolor,$fgcolor,$lw);
#      $self->filled_box($gd,$x1,$y_origin-9,$x2,$part->{_y_position}-15,$negcolor,$fgcolor,$lw);
    }
  }

  # That's it.
}
# 
# sub _draw_line {
#   my $self = shift;
#   my ($gd,$left,$top) = @_;
# 
#   my @parts  = $self->parts;
#   my $fgcolor = $self->fgcolor;
#   my $bgcolor = $self->bgcolor;
# 
#   # connect to center positions of each interval
#   my $first_part = shift @parts;
# #  my ($x1,$x2) = ($first_part->{left},$first_part->{left}+$first_part->{width}-1);
#   my ($x1,$y1,$x2,$y2) = $first_part->calculate_boundaries($left,$top);
#   my $current_x = ($x1+$x2)/2;
#   my $current_y = $first_part->{_y_position};
# 
#   for my $part (@parts) {
# #    ($x1,$x2) = ($part->{left},$part->{left}+$part->{width}-1);
#     ($x1,$y1,$x2,$y2) = $part->calculate_boundaries($left,$top);
#     my $next_x = ($x1+$x2)/2;
#     my $next_y = $part->{_y_position};
#     $gd->line($current_x,$current_y,$next_x,$next_y,$fgcolor);
#     ($current_x,$current_y) = ($next_x,$next_y);
#   }
# 
# }
# 
# sub _draw_points {
#   my $self = shift;
#   my ($gd,$left,$top) = @_;
#   my $symbol_name = $self->option('point_symbol') || 'point';
#   my $filled      = $symbol_name =~ s/^filled_//;
#   my $symbol_ref  = $SYMBOLS{$symbol_name};
# 
#   my @parts   = $self->parts;
#   my $fgcolor = $self->fgcolor;
#   my $bgcolor = $self->bgcolor;
#   my $pr      = $self->point_radius;
# 
#   my $partcolor = $self->code_option('part_color');
#   my $factory  = $self->factory;
# 
#   for my $part (@parts) {
# #    my ($x1,$x2) = ($part->{left},$part->{left}+$part->{width}-1);
#     my ($x1,$y1,$x2,$y2) = $part->calculate_boundaries($left,$top);
#     my $x = ($x1+$x2)/2;
#     my $y = $part->{_y_position};
# 
#     my $color;
#     if ($partcolor) {
#       $color    = $factory->translate_color($factory->option($part,'part_color',0,0));
#     } else {
#       $color    = $fgcolor;
#     }
# 
#     $symbol_ref->($gd,$x,$y,$pr,$color,$filled);
#   }
# }
# 
# sub _determine_side
# {
#   my $self = shift;
#   my $side = $self->option('scale');
#   return if $side eq 'none';
#   $side   ||= $self->default_scale();
#   return $side;
# }
# 
sub _draw_scale {
  my $self = shift;
  print LOG "\n_draw_scale()\n" if ($debug);
  my ($gd,$scale,$min,$max,$dx,$dy,$y_origin,$force_zero) = @_;
  my ($x1,$y1,$x2,$y2) = $self->calculate_boundaries($dx,$dy);
	my ($iwidth,$iheight) = $gd->getBounds();
 	$x1 = 1;
 	$x2 = $iwidth - 1;
	$y_origin = ($min+$max)/2 if ($force_zero);
#	$y_origin = ($y1 + $y2)/2 if ($min < 0);
	#$x1 = $x2 = $x3;
  # this is wrong
  #  $y2 -= $self->pad_bottom - 1;
#	print LOG "width = $iwidth\n";

  my $side = $self->_determine_side();

  my $fg    = $self->scalecolor;
  my $font  = $self->font('gdTinyFont');
	print LOG "x1 = $x1\nx2 = $x2\ny1 = $y1\ny2 = $y2\nscale = $scale\n" if ($debug);
	print LOG "min = $min\nmax = $max\ndx = $dx\ndy = $dy\ny_origin = $y_origin\n" if ($debug);
	print LOG "side = $side\nfg = $fg\nfont height = " . $font->height(), "\n" if ($debug);
#$gd->line($x1,$y1,$x1,$y_origin,$fg) if $side eq 'left'  || $side eq 'both';
#$gd->line($x2,$y1,$x2,$y_origin,$fg) if $side eq 'right' || $side eq 'both';
	
#	$gd->line($x2,$y1,$x2,$y2,$fg);# vertical line of right scale bar
#	$gd->line($x1,$y1,$x1,$y2,$fg);# vertical line of left scale bar 48
#  $gd->line($x1,$y_origin,$x2,$y_origin,$fg);# horizontal line through origin 

	$gd->line($x2,$self->score2position($max),$x2,$self->score2position($min),$fg);# vertical line of right scale bar
	$gd->line($x1,$self->score2position($max),$x1,$self->score2position($min),$fg);# vertical line of left scale bar 48


	my @points = ();
	if ($min == $max) {
		@points = ([$y2,$max],[$y_origin,'0']);
	} elsif ($min >= 0) {
  	@points = ([$self->score2position($max),$max],[$self->score2position(($min+$max) * 0.75),($min+$max) * 0.75],[$self->score2position(($min+$max)/2),($min+$max)/2],[$self->score2position(($min+$max)/4),($min+$max)/4],[$self->score2position($min),$min]);#SAG	
#  	@points = ([$y1,$max],[($y1+$y2)/2,($min+$max)/2],[$y_origin,$min]);#SAG
#  push @points,[$y_origin,0] if ($min < 0 && $max > 0);
#  	push @points,[$y2,0] if ($min < 0 && $max > 0);
	} else {
  	@points = ([$self->score2position($max),$max],[$self->score2position($max * 0.5),$max * 0.5],[$self->score2position($min),$min],[$self->score2position(0.01),'0'],[$self->score2position($min/2),$min/2]);#SAG	
#  	@points = ([$y1,$max],[($y1+$y2)/2,($min+$max)/2],[$y_origin,'0']);
#  	@points = ([$y1,$max],[($y1+$y2)/2,($min+$max)/2],[$y_origin,'0']);#SAG
#  	push @points,[$y2,$min];# if ($min < 0 && $max > 0);
	}

  my $last_font_pos = -99999999999;

  for (sort { $b->[1] <=> $a->[1] } @points) {
#    $gd->line($x1-3,$_->[0],$x1,$_->[0],$fg) if $side eq 'left'  || $side eq 'both';
#    $gd->line($x2,$_->[0],$x2+3,$_->[0],$fg) if $side eq 'right' || $side eq 'both';
#    $gd->line($x1-3,$_->[0],$x1,$_->[0],$fg) if $side eq 'left'  || $side eq 'both';
		print LOG "point: " . $_->[0] . " : " . $_->[1] . "\n" if ($debug);
#		ticks of right scale bar
#		print LOG "printing right scale tick for $_->[1]\n" if ($debug);
    $gd->line($x2,$_->[0],$x2-5,$_->[0],$fg) if $side eq 'right' || $side eq 'both';
#		print LOG "printing left scale tick for $_->[1]\n" if ($debug);
#		ticks of left scale bar
    $gd->line($x1,$_->[0],$x1+5,$_->[0],$fg) if $side eq 'right' || $side eq 'both';# ticks of scale bar

    my $font_pos = $_->[0]-($font->height/2);
#		print LOG "font_pos = $font_pos\nlast_font_pos = $last_font_pos\n";
    next unless $font_pos > $last_font_pos + $font->height; # prevent labels from clashing
#     if ($side eq 'left' or $side eq 'both') {
#       $gd->string($font,
# 		  $x1 - $font->width * length($_->[1]) - 3,$font_pos,
# 		  $_->[1],
# 		  $fg);
#     }
#
#
#			left scale numbers
#
			print LOG "printing '", $_->[1], "' at $font_pos\n" if ($debug);
      $gd->string($font,
		  $x1+6,$font_pos,
		  $_->[1],
		  $fg);

#     if ($side eq 'right' or $side eq 'both') {
#       $gd->string($font,
# 		  $x2 + 5,$font_pos,
# 		  $_->[1],
# 		  $fg);
#     }
#
#
#			right scale numbers
#
      $gd->string($font,
		  ($x2 - 6) - $font->width * length($_->[1]) - 1,$font_pos,
		  $_->[1],
		  $fg);

			$gd->line($x1+2 + ($x1 + 7 + $font->width * length($_->[1]) +2),$_->[0],$x2 - $font->width * length($_->[1]) - 16,$_->[0],$gd->colorAllocate(200,200,200));
		#print LOG $_->[1] . " has width = " . $font->width * length($_->[1]) . "\n";
   $last_font_pos = $font_pos;
  }

}
# 
# # we are unbumpable!
# sub bump {
#   return 0;
# }
# 
# sub connector {
#   my $self = shift;
#   my $type = $self->option('graph_type');
#   return 1 if $type eq 'line' or $type eq 'linepoints';
# }
# 
# sub height {
#   my $self = shift;
#   return $self->option('graph_height') || $self->SUPER::height;
# }
# 
# sub draw_triangle {
#   my ($gd,$x,$y,$pr,$color,$filled) = @_;
#   $pr /= 2;
#   my ($vx1,$vy1) = ($x-$pr,$y+$pr);
#   my ($vx2,$vy2) = ($x,  $y-$pr);
#   my ($vx3,$vy3) = ($x+$pr,$y+$pr);
#   my $poly = GD::Polygon->new;
#   $poly->addPt($vx1,$vy1,$vx2,$vy2);
#   $poly->addPt($vx2,$vy2,$vx3,$vy3);
#   $poly->addPt($vx3,$vy3,$vx1,$vy1);
#   if ($filled) {
#     $gd->filledPolygon($poly,$color);
#   } else {
#     $gd->polygon($poly,$color);
#   }
# }
# 
# sub draw_square {
#   my ($gd,$x,$y,$pr,$color,$filled) = @_;
#   $pr /= 2;
#   my $poly = GD::Polygon->new;
#   $poly->addPt($x-$pr,$y-$pr);
#   $poly->addPt($x+$pr,$y-$pr);
#   $poly->addPt($x+$pr,$y+$pr);
#   $poly->addPt($x-$pr,$y+$pr);
#   if ($filled) {
#     $gd->filledPolygon($poly,$color);
#   } else {
#     $gd->polygon($poly,$color);
#   }
# }
# sub draw_disc {
#   my ($gd,$x,$y,$pr,$color,$filled) = @_;
#   if ($filled) {
#     $gd->filledArc($x,$y,$pr,$pr,0,360,$color);
#   } else {
#     $gd->arc($x,$y,$pr,$pr,0,360,$color);
#   }
# }
# sub draw_point {
#   my ($gd,$x,$y,$pr,$color) = @_;
#   $gd->setPixel($x,$y,$color);
# }
# 
# sub keyglyph {
#   my $self = shift;
# 
#   my $scale = 1/$self->scale;  # base pairs/pixel
# 
#   my $feature =
#     Bio::Graphics::Feature->new(
# 				-segments=>[ [ 0*$scale,9*$scale],
# 					     [ 10*$scale,19*$scale],
# 					     [ 20*$scale, 29*$scale]
# 					   ],
# 				-name => 'foo bar',
# 				-strand => '+1');
#   ($feature->segments)[0]->score(10);
#   ($feature->segments)[1]->score(50);
#   ($feature->segments)[2]->score(25);
#   my $factory = $self->factory->clone;
#   $factory->set_option(label => 1);
#   $factory->set_option(bump  => 0);
#   $factory->set_option(connector  => 'solid');
#   my $glyph = $factory->make_glyph(0,$feature);
#   return $glyph;
# }

#
# subclass filled_box from Bio::Graphics::Glyph
#
sub filled_box {
  my $self = shift;
  my $gd = shift;
  my ($x1,$y1,$x2,$y2,$bg,$fg,$force_zero) = @_;# $y2 is y_origin
  my $font  = $self->font('gdTinyFont');
	
if ($debug) {
		print LOG "\nfilled_box()\n";
		print LOG "x1 = $x1, y1 = $y1\nx2 = $x2, y2 = $y2\n";
		print LOG "self height = " . $self->height() . "\n";
	}
  $bg ||= $self->bgcolor;
  $fg ||= $self->fgcolor;
  my $linewidth = $self->option('linewidth') || 1;

#  $gd->filledRectangle($x1,$y1-$self->pad_top,$x2,$y2-int($self->pad_top/2)-1,$bg);
  $gd->filledRectangle($x1,$y1,$x2,$y2,$bg);


#	$gd->string($font,$x1,$y2,$y1,$fg);


#$fg = $self->set_pen($linewidth,$fg) if $linewidth > 1;

# draw a box
#$gd->rectangle($x1,$y1,$x2,$y2,$fg);

# if the left end is off the end, then cover over
# the leftmost line
  my ($width) = $gd->getBounds;

  $bg = $self->set_pen($linewidth,$bg) if $linewidth > 1;

  $gd->line($x1,$y1+$linewidth,$x1,$y2-$linewidth,$bg)
    if $x1 < $self->panel->pad_left;

  $gd->line($x2,$y1+$linewidth,$x2,$y2-$linewidth,$bg)
    if $x2 > $width - $self->panel->pad_right;
}


1;

__END__

=head1 NAME

Bio::Graphics::Glyph::xyplot - The xyplot glyph

=head1 SYNOPSIS

  See L<Bio::Graphics::Panel> and L<Bio::Graphics::Glyph>.

=head1 DESCRIPTION

This glyph is used for drawing features that have a position on the
genome and a numeric value.  It can be used to represent gene
prediction scores, motif-calling scores, percent similarity,
microarray intensities, or other features that require a line plot.

The X axis represents the position on the genome, as per all other
glyphs.  The Y axis represents the score.  Options allow you to set
the height of the glyph, the maximum and minimum scores, the color of
the line and axis, and the symbol to draw.

The plot is designed to work on a single feature group that contains
subfeatures.  It is the subfeatures that carry the score
information. The best way to arrange for this is to create an
aggregator for the feature.  We'll take as an example a histogram of
repeat density in which interval are spaced every megabase and the
score indicates the number of repeats in the interval; we'll assume
that the database has been loaded in in such a way that each interval
is a distinct feature with the method name "density" and the source
name "repeat".  Furthermore, all the repeat features are grouped
together into a single group (the name of the group is irrelevant).
If you are using Bio::DB::GFF and Bio::Graphics directly, the sequence
of events would look like this:

  my $agg = Bio::DB::GFF::Aggregator->new(-method    => 'repeat_density',
                                          -sub_parts => 'density:repeat');
  my $db  = Bio::DB::GFF->new(-dsn=>'my_database',
                              -aggregators => $agg);
  my $segment  = $db->segment('Chr1');
  my @features = $segment->features('repeat_density');

  my $panel = Bio::Graphics::Panel->new(-pad_left=>40,-pad_right=>40);
  $panel->add_track(\@features,
                    -glyph => 'xyplot',
  		    -graph_type=>'points',
		    -point_symbol=>'disc',
		    -point_radius=>4,
		    -scale=>'both',
		    -height=>200,
  );

If you are using Generic Genome Browser, you will add this to the
configuration file:

  aggregators = repeat_density{density:repeat}
                clone alignment etc

Note that it is a good idea to add some padding to the left and right
of the panel; otherwise the scale will be partially cut off by the
edge of the image.

=head2 OPTIONS

The following options are standard among all Glyphs.  See
L<Bio::Graphics::Glyph> for a full explanation.

  Option      Description                      Default
  ------      -----------                      -------

  -fgcolor      Foreground color	       black

  -outlinecolor	Synonym for -fgcolor

  -bgcolor      Background color               turquoise

  -fillcolor    Synonym for -bgcolor


  -linewidth    Line width                     1

  -height       Height of glyph		       10

  -font         Glyph font		       gdSmallFont

  -label        Whether to draw a label	       0 (false)

  -description  Whether to draw a description  0 (false)

  -hilite       Highlight color                undef (no color)

In addition, the alignment glyph recognizes the following
glyph-specific options:

  Option         Description                  Default
  ------         -----------                  -------

  -max_score   Maximum value of the	      Calculated
               feature's "score" attribute

  -min_score   Minimum value of the           Calculated
               feature's "score" attributes

  -graph_type  Type of graph to generate.     Histogram
               Options are: "histogram",
               "boxes", "line", "points",
               or "linepoints".

  -point_symbol Symbol to use. Options are    none
                "triangle", "square", "disc",
                "filled_triangle",
                "filled_square",
                "filled_disc","point",
                and "none".

  -point_radius Radius of the symbol, in      4
                pixels (does not apply
                to "point")

  -scale        Position where the Y axis     none
                scale is drawn if any.
                It should be one of
                "left", "right", "both" or "none"

  -graph_height Specify height of the graph   Same as the
                                              "height" option.

  -neg_color   For boxes only, bgcolor for    Same as bgcolor
               points with negative scores

  -part_color  For boxes & points only,       none
               bgcolor of each part (should
               be a callback). Supersedes
               -neg_color.

  -scale_color Color of the scale             Same as fgcolor

  -clip        If min_score and/or max_score  false
               are manually specified, then
               setting this to true will
               cause values outside the
               range to be clipped.

Note that when drawing scales on the left or right that the scale is
actually drawn a few pixels B<outside> the boundaries of the glyph.
You may wish to add some padding to the image using -pad_left and
-pad_right when you create the panel.

The B<-part_color> option can be used to color each part of the
graph. Only the "boxes", "points" and "linepoints" styles are
affected by this.  Here's a simple example:

  $panel->add_track->(\@affymetrix_data,
                      -glyph      => 'xyplot',
                      -graph_type => 'boxes',
                      -part_color => sub {
                                   my $score = shift->score;
	                           return 'red' if $score < 0;
	                           return 'lightblue' if $score < 500;
                                   return 'blue'      if $score >= 500;
                                  }
                      );

=head2 METHODS

For those developers wishing to derive new modules based on this
glyph, the main method to override is:

=over 4

=item 'method_name' = $glyph-E<gt>lookup_draw_method($type)

This method accepts the name of a graph type (such as 'histogram') and
returns the name of a method that will be called to draw the contents
of the graph, for example '_draw_histogram'. This method will be
called with three arguments:

   $self->$draw_method($gd,$left,$top,$y_origin)

where $gd is the GD object, $left and $top are the left and right
positions of the whole glyph (which includes the scale and label), and
$y_origin is the position of the zero value on the y axis (in
pixels). By the time this method is called, the y axis and labels will
already have been drawn, and the scale of the drawing (in pixels per
unit score) will have been calculated and stored in
$self-E<gt>{_scale}. The y position (in pixels) of each point to graph
will have been stored into the part, as $part-E<gt>{_y_position}. Hence
you could draw a simple scatter plot with this code:

 sub lookup_draw_method {
    my $self = shift;
    my $type = shift;
    if ($type eq 'simple_scatterplot') {
      return 'draw_points';
    } else {
      return $self->SUPER::lookup_draw_method($type);
    }
 }

 sub draw_points {
  my $self = shift;
  my ($gd,$left,$top) = @_;
  my @parts   = $self->parts;
  my $bgcolor = $self->bgcolor;

  for my $part (@parts) {
    my ($x1,$y1,$x2,$y2) = $part->calculate_boundaries($left,$top);
    my $x = ($x1+$x2)/2;  # take center
    my $y = $part->{_y_position};
    $gd->setPixel($x,$y,$bgcolor);
 }

lookup_draw_method() may return multiple method names if needed. Each
will be called in turn.

=item $y_position = $self-E<gt>score2position($score)

Translate a score into a y pixel position, obeying clipping rules and
min and max values.

=back

=head1 BUGS

Please report them.

=head1 SEE ALSO

L<Bio::Graphics::Panel>,
L<Bio::Graphics::Track>,
L<Bio::Graphics::Glyph::transcript2>,
L<Bio::Graphics::Glyph::anchored_arrow>,
L<Bio::Graphics::Glyph::arrow>,
L<Bio::Graphics::Glyph::box>,
L<Bio::Graphics::Glyph::primers>,
L<Bio::Graphics::Glyph::segments>,
L<Bio::Graphics::Glyph::toomany>,
L<Bio::Graphics::Glyph::transcript>,

=head1 AUTHOR

Lincoln Stein E<lt>lstein@cshl.orgE<gt>

Copyright (c) 2001 Cold Spring Harbor Laboratory

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.  See DISCLAIMER.txt for
disclaimers of warranty.

=cut


