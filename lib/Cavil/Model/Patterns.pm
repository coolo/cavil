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

package Cavil::Model::Patterns;
use Mojo::Base -base;

use Mojo::File 'path';
use Spooky::Patterns::XS;
use Storable;

has [qw(cache log pg)];

sub create {
  my ($self, $id, %args) = @_;

  my $mid = $self->pg->db->insert(
    'license_patterns',
    {
      license      => $id,
      pattern      => $args{pattern},
      token_hexsum => $self->checksum($args{pattern}),
      packname     => $args{packname} // '',
      patent       => $args{patent} // 0,
      trademark    => $args{trademark} // 0,
      opinion      => $args{opinion} // 0
    },
    {returning => 'id'}
  )->hash->{id};

  return $self->find($mid);
}

sub expire_cache { unlink path(shift->cache, 'cavil.tokens')->to_string }

sub has_new_patterns {
  my ($self, $packname, $when) = @_;
  return $self->pg->db->query(
    "select count(*) from license_patterns
     where created > ? and (packname = '' or packname = ?)", $when, $packname
  )->array->[0];
}

sub load_specific {
  my ($self, $matcher, $pname) = @_;

  my $rows = $self->pg->db->select(
    'license_patterns',
    ['id', 'pattern'],
    {packname => $pname}
  );

  while (my $l = $rows->array) {
    my ($id, $pattern) = @$l;
    $pattern = Spooky::Patterns::XS::parse_tokens($pattern);
    $matcher->add_pattern($id, $pattern);
  }
}

# possibly cached
sub load_unspecific {
  my ($self, $matcher) = @_;

  my $cachefile = path($self->cache, 'cavil.tokens')->to_string;
  if (-f $cachefile) {
    $matcher->load($cachefile);
    return;
  }

  $self->load_specific($matcher, '');

  my $dir = path($self->cache);
  my $tmp = $dir->child("cavil.tokens.tmp.$$")->to_string;
  $matcher->dump($tmp);
  rename $tmp, $cachefile;
}

sub find {
  my ($self, $id) = @_;
  return $self->pg->db->select('license_patterns', '*', {id => $id})->hash;
}

sub checksum {
  my ($self, $pattern) = @_;

  Spooky::Patterns::XS::init_matcher();
  my $a   = Spooky::Patterns::XS::parse_tokens($pattern);
  my $ctx = Spooky::Patterns::XS::init_hash(0, 0);
  for my $n (@$a) {

    # map the skips to each other
    $n = 99 if $n < 99;
    my $s = pack('q', $n);
    $ctx->add($s);
  }

  return $ctx->hex;
}

sub for_license {
  my ($self, $id) = @_;
  return $self->pg->db->select('license_patterns', '*', {license => $id},
    'created')->hashes->to_array;
}

sub remove {
  my ($self, $id) = @_;
  $self->pg->db->delete('license_patterns', {id => $id});
}

sub update {
  my ($self, $id, %args) = @_;

  $self->pg->db->update(
    'license_patterns',
    {
      pattern      => $args{pattern},
      token_hexsum => $self->checksum($args{pattern}),
      packname     => $args{packname} // '',
      license      => $args{license},
      patent       => $args{patent} // 0,
      trademark    => $args{trademark} // 0,
      opinion      => $args{opinion} // 0
    },
    {id => $id}
  );
}

1;