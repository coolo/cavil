# Copyright (C) 2019 SUSE Linux GmbH
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package Cavil::PostProcess;
use Mojo::Base -base;

has 'hash';

sub _split_find_a_good_spot {
  my ($line, $max_line_length) = @_;

  my $index  = $max_line_length;
  my $length = length($line);
  return $length if ($index > $length);
  my %splits = (' ' => 1, ';' => 1, '{' => 1, '}' => 1, '"' => 0);
  while ($index > $max_line_length * 0.7) {
    my $char = substr($line, $index, 1);
    return $index + $splits{$char} if (exists $splits{$char});
    $index--;
  }

  # now look further down
  $index = $max_line_length;
  while ($index < $length) {
    my $char = substr($line, $index, 1);
    return $index + $splits{$char} if (exists $splits{$char});
    $index++;
  }
  return 0;
}

sub _split_line_by_whitespace {
  my ($fh, $line, $max_line_length) = @_;

  my $changed;
  while ($line) {
    my $index = _split_find_a_good_spot($line, $max_line_length);
    if (!$index) {
      print $fh $line;
      print $fh "\n";
      last;
    }

    my $first = substr($line, 0, $index);
    print $fh $first;
    print $fh "\n";
    $line    = substr($line, $index);
    $changed = 1;
  }
  return $changed;
}

sub _split_lines {
  my ($destdir, $from, $max_line_length) = @_;

  # avoid doing it again
  return undef if $from =~ m/.max-lined/;
  my $to;
  if ($from =~ m,^(.*)\.([^./]+$),) {
    $to = "$1.max-lined.$2";
  }
  else {
    $to = "$from.max-lined";
  }

  open(my $f_in,  '<', "$destdir/$from") || die "Can't open $from";
  open(my $f_out, '>', "$destdir/$to")   || die "Can't open $to";

  my $changed = 0;
  while (<$f_in>) {
    my $line = $_;
    if (length($line) > $max_line_length) {
      chomp $line;
      $changed = _split_line_by_whitespace($f_out, $line, $max_line_length)
        || $changed;
    }
    else {
      print $f_out $line;
    }
  }

  close($f_in);
  close($f_out);

  if (!$changed) {
    unlink($to);
    return undef;
  }
  return $to;
}

sub new { shift->SUPER::new(hash => shift) }

sub postprocess {
  my $self = shift;

  for my $fname (keys %{$self->hash->{unpacked}}) {
    my $entry = $self->hash->{unpacked}{$fname};
    next if exists $entry->{unpacked} || $entry->{mime} !~ m,text/,;

    my $max_line_length = 125;
    my $new_fname
      = _split_lines($self->hash->{destdir}, $fname, $max_line_length);
    next unless $new_fname;
    $self->hash->{unpacked}{$new_fname} = {mime => $entry->{mime}};
    delete $self->hash->{unpacked}{$fname};
  }
}


1;
