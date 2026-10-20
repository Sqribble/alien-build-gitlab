package Alien::Build::Plugin::Download::GitLab;

use strict;
use warnings;
use 5.008004;
use Carp qw( croak );
use URI;
use JSON::PP qw( decode_json );
use URI::Escape qw( uri_escape );
use Alien::Build::Plugin;
use File::Basename qw( basename );
use Path::Tiny qw( path );

# ABSTRACT: Alien::Build plugin to download from GitLab
our $VERSION = '0.03'; # VERSION

=head1 SYNOPSIS

 use alienfile;

 plugin 'Download::GitLab' => (
   gitlab_user    => 'plicease',
   gitlab_project => 'dontpanic',
 );

=head1 DESCRIPTION

Download release assets from a GitLab instance.

This is a cleaned edition of the original module by Graham Ollis
(plicease). The original distribution is on MetaCPAN and at
L<https://github.com/PerlAlien/Alien-Build-Plugin-Download-GitLab>.

Besides formatting, this edition:

=over 4

=item *

Fixes the syntax error in the upstream C<link> branch
(C<my $filename =E<gt> ...> is not valid Perl).

=item *

Implements the upstream TODO for a private token. The token is sent
as a C<PRIVATE-TOKEN> header only to the configured GitLab host, and
it is redacted from the Alien::Build log.

=item *

Ignores a missing C<assets> / C<sources> / C<links> list instead of
crashing, and turns a GitLab error object into a clear exception.

=item *

Requests the newest 100 releases explicitly (C<per_page=100>,
C<sort=desc>) instead of relying on the API default page size.

=back

=head1 PROPERTIES

=head2 gitlab_host

GitLab instance to fetch from. Defaults to L<https://gitlab.com>.
Include the scheme, for example C<https://gitlab.example.com>.

=head2 gitlab_user

User or group that owns the project. Required. For a project under
subgroups, put the group path here (C<group/subgroup>) and the project
name in C<gitlab_project>.

=head2 gitlab_project

Project to fetch from. Required.

=head2 type

Asset type to fetch. One of C<source> or C<link>. Default: C<source>.

=head2 format

Expected format of a C<source> asset, as understood by
L<Alien::Build::Plugin::Extract::Negotiate>. GitLab reports this as
C<tar.gz>, C<tar.bz2>, C<tar>, or C<zip>. Default: C<tar.gz>.

=head2 version_from

Where to read the version. One of C<tag_name> or C<name>.
Default: C<tag_name>.

=head2 convert_version

Optional code reference that may rewrite the version. To strip a
leading C<v>:

 plugin 'Download::GitLab' => (
   gitlab_user     => 'plicease',
   gitlab_project  => 'dontpanic',
   convert_version => sub {
     my $version = shift;
     $version =~ s/^v//;
     return $version;
   },
 );

=head2 link_name

For C<link> assets, a regular expression tested against the filename.
Example: C<qr/\.tar\.gz$/>. Links on another host never receive the
GitLab token.

=cut

has gitlab_host    => 'https://gitlab.com';
has gitlab_user    => undef;
has gitlab_project => undef;

has type => 'source';  # source or link

has format => 'tar.gz';

has version_from    => 'tag_name'; # tag_name or name
has convert_version => undef;
has link_name       => undef;

my $logged_token = 0;

# True when $target is the same scheme, host, and port as the configured
# GitLab instance. Used so a private token is never sent anywhere else.
sub _same_endpoint
{
  my($configured_host, $target) = @_;

  return 0 unless defined $target && length $target;

  my $want = URI->new($configured_host);
  my $got  = eval { URI->new($target) };
  return 0 if !$got || $@;
  return 0 unless defined $got->host && defined $want->host;
  return 0 unless lc($got->scheme // '') eq lc($want->scheme // '');
  return 0 unless lc($got->host) eq lc($want->host);
  return ($got->port // 0) == ($want->port // 0);
}

# True when $target is the releases index this plugin configured.
sub _is_release_index
{
  my($start_url, $target) = @_;

  return 0 unless defined $start_url && defined $target && length $target;
  return 1 if $target eq $start_url;

  my $start = eval { URI->new($start_url) };
  my $got   = eval { URI->new($target) };
  return 0 if !$start || !$got || $@;
  return 0 unless defined $got->host && defined $start->host;
  return 0 unless lc($got->scheme // '') eq lc($start->scheme // '');
  return 0 unless lc($got->host) eq lc($start->host);
  return 0 unless ($got->port // 0) == ($start->port // 0);
  return ($got->path // '') eq ($start->path // '');
}

sub _releases_url
{
  my($self) = @_;

  my $project_path = join '/', $self->gitlab_user, $self->gitlab_project;
  my $url = URI->new($self->gitlab_host);
  # The project path is one path segment; '/' must stay percent-encoded.
  $url->path('/api/v4/projects/' . uri_escape($project_path) . '/releases');
  $url->query_form(
    per_page => 100,
    order_by => 'released_at',
    sort     => 'desc',
  );
  return "$url";
}

sub _candidates_from_releases
{
  my($self, $rel) = @_;

  my @list;

  foreach my $release (@$rel)
  {
    next unless ref $release eq 'HASH';

    my $version = $self->version_from eq 'name'
      ? $release->{name}
      : $release->{tag_name};
    $version = $self->convert_version->($version) if $self->convert_version;

    my $assets = ref($release->{assets}) eq 'HASH' ? $release->{assets} : {};

    if($self->type eq 'source')
    {
      my $sources = ref($assets->{sources}) eq 'ARRAY' ? $assets->{sources} : [];
      foreach my $source (@$sources)
      {
        next unless ref $source eq 'HASH';
        next unless defined $source->{format} && $source->{format} eq $self->format;
        next unless defined $source->{url} && length $source->{url};
        my $src_url  = URI->new($source->{url});
        my $filename = basename($src_url->path);
        push @list, {
          filename => $filename,
          url      => $source->{url},
          version  => $version,
        };
      }
    }
    else # link
    {
      my $links = ref($assets->{links}) eq 'ARRAY' ? $assets->{links} : [];
      foreach my $link (@$links)
      {
        next unless ref $link eq 'HASH';
        next unless defined $link->{url} && length $link->{url};
        my $link_url = URI->new($link->{url});
        my $filename = basename($link_url->path);
        if($self->link_name)
        {
          next unless $filename =~ $self->link_name;
        }
        push @list, {
          filename => $filename,
          url      => $link->{url},
          version  => $version,
        };
      }
    }
  }

  return \@list;
}

sub _redact
{
  my($secret, $text) = @_;
  return $text unless defined $secret && defined $text && length $secret;
  $text =~ s/\Q$secret\E/ '#' x length($secret) /eg;
  return $text;
}

sub init
{
  my($self, $meta) = @_;

  croak("No gitlab_user provided")
    unless defined $self->gitlab_user && $self->gitlab_user ne '';
  croak("No gitlab_project provided")
    unless defined $self->gitlab_project && $self->gitlab_project ne '';
  croak("Don't set a start_url with the Download::GitLab plugin")
    if defined $meta->prop->{start_url};
  croak("type must be one of source or link")
    if !defined $self->type || $self->type !~ /^(source|link)$/;
  croak("version_from must be one of tag_name or name")
    if !defined $self->version_from || $self->version_from !~ /^(tag_name|name)$/;

  $meta->add_requires('configure' => 'Alien::Build::Plugin::Download::GitLab' => '0.03');

  my $start_url = $self->_releases_url;
  $meta->prop->{start_url} = $start_url;

  $meta->apply_plugin('Download');
  $meta->apply_plugin('Extract', format => $self->format);

  # Newest release first (sort=desc). A later prefer plugin can replace this.
  $meta->register_hook(
    prefer => sub {
      my($build, $res) = @_;
      return $res;
    },
  );

  my %gl_fetch_options;
  my $secret;
  my $secret_from;

  foreach my $name (qw( ALIEN_BUILD_GITLAB_TOKEN GITLAB_TOKEN GITLAB_PRIVATE_TOKEN ))
  {
    if(defined $ENV{$name} && $ENV{$name} ne '')
    {
      $secret = $ENV{$name};
      $secret_from = $name;
      # Fetch plugins expect http_headers as an array of name/value pairs.
      push @{ $gl_fetch_options{http_headers} }, 'PRIVATE-TOKEN' => $secret;
      last;
    }
  }

  my $gitlab_host = $self->gitlab_host;

  $meta->around_hook(
    fetch => sub {
      my $orig = shift;
      my($build, $url, @the_rest) = @_;

      my $target = (defined $url && length $url) ? $url : $start_url;
      my $on_gitlab = _same_endpoint($gitlab_host, $target);

      return $orig->($build, $url, @the_rest) unless $on_gitlab;

      if(defined $secret && !$logged_token)
      {
        Alien::Build->log("using the GitLab private token in $secret_from");
        $logged_token = 1;
      }

      my $log = \&Alien::Build::log;
      no warnings 'redefine';
      local *Alien::Build::log = sub {
        if(defined $_[1])
        {
          $_[1] = _redact($secret, $_[1]);
        }
        goto &$log;
      };
      use warnings;

      my $res = defined $secret
        ? $orig->($build, $url, @the_rest, %gl_fetch_options)
        : $orig->($build, $url, @the_rest);

      return $res unless _is_release_index($start_url, $target);

      my $res2 = {
        type => 'list',
        list => [],
      };

      $res2->{protocol} = $res->{protocol}
        if ref $res eq 'HASH' && exists $res->{protocol};

      my $raw;
      if(ref $res eq 'HASH' && defined $res->{content})
      {
        $raw = $res->{content};
      }
      elsif(ref $res eq 'HASH' && defined $res->{path})
      {
        $raw = path($res->{path})->slurp_raw;
      }
      else
      {
        croak('malformed response object: no content or path');
      }

      my $rel = eval { decode_json $raw };
      if($@ || !defined $rel)
      {
        my $err = _redact($secret, $@ || 'empty body');
        croak("GitLab releases API did not return JSON: $err");
      }
      unless(ref $rel eq 'ARRAY')
      {
        my $msg = ref $rel eq 'HASH' && defined $rel->{message}
          ? $rel->{message}
          : 'expected a JSON array of releases';
        croak(_redact($secret, "GitLab releases API error: $msg"));
      }

      $res2->{list} = $self->_candidates_from_releases($rel);
      return $res2;
    },
  );
}

1;

__END__

=head1 ENVIRONMENT

=over 4

=item ALIEN_BUILD_GITLAB_TOKEN, GITLAB_TOKEN, GITLAB_PRIVATE_TOKEN

If one of these is set and non-empty, that value is sent as a
C<PRIVATE-TOKEN> header. The first name in the list above that is set
wins.

The header is added only when the request URL has the same scheme,
host, and port as C<gitlab_host>. Archive downloads on that host (the
usual C<source> URLs of a private project) are authenticated. Link
assets hosted elsewhere are not. The token is stripped from log lines
before they are printed.

Personal, project, and group access tokens all use this header.

=back

=head1 CAVEATS

Only the newest 100 releases are considered. That is GitLab's maximum
page size.

This plugin does not follow C<Link> pagination past that page.

=head1 SEE ALSO

=over 4

=item L<Alien>

=item L<Alien::Build::Plugin::Download::GitHub>

=item L<alienfile>

=item L<Alien::Build>

=item L<https://github.com/PerlAlien/Alien-Build-Plugin-Download-GitLab>

=back

=head1 AUTHOR

Original author: Graham Ollis <plicease@cpan.org>

Cleaned edition maintained as a personal fork.

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2022 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
