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

package Cavil::Controller::Snippet;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON 'decode_json';
use Cavil::Text 'closest_pattern';

sub list {
  my $self = shift;

  $self->render(snippets => $self->snippets->random(100));
}

sub update {
  my $self = shift;

  my $db     = $self->pg->db;
  my $params = $self->req->params->to_hash;
  for my $param (sort keys %$params) {
    next unless $param =~ m/g_(\d+)/;
    my $id      = $1;
    my $license = $params->{$param};
    $db->update(
      'snippets',
      {license => $license, approved => 1, classified => 1},
      {id      => $id}
    );
  }
  $self->redirect_to('snippets');
}

sub edit {
  my $self = shift;

  my $id      = $self->param('id');
  my $snippet = $self->snippets->find($id);

  Spooky::Patterns::XS::init_matcher();

  my $cache = $self->app->home->child('cache', 'cavil.pattern.words');
  my $data  = decode_json $cache->slurp;

  my ($best, $sim) = closest_pattern($snippet->{text}, undef, $data);
  $best = $self->patterns->find($best->{id});

  $self->render(
    snippet    => $snippet,
    best       => $best,
    similarity => int($sim * 1000 + 0.5) / 10
  );
}

# proxy function
sub decision {
  my $self = shift;

  my $db = $self->pg->db;

  if ($self->param('create-pattern')) {
    my $match = $self->patterns->create(
      license => $self->param('license'),
      pattern => $self->param('pattern'),
      risk    => $self->param('risk'),

      # TODO: those checkboxes aren't yet taken over
      eula      => $self->param('eula'),
      nonfree   => $self->param('nonfree'),
      patent    => $self->param('patent'),
      trademark => $self->param('trademark'),
      opinion   => $self->param('opinion')
    );
    $self->flash(success => 'Pattern has been created.');
    $self->redirect_to('edit_pattern', id => $match->{id});
    return;
  }
  elsif ($self->param('mark-non-license')) {
    $self->snippets->mark_non_license($self->params('id'));
  }
  $self->render(text => 'ok');
}

1;
