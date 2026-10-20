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
our $VERSION = '0.02'; # VERSION

=head1 SYNOPSIS

 use alienfile;
 
 plugin 'Download::GitLab' => (
   gitlab_user    => 'plicease',
   gitlab_project => 'dontpanic',
 );

=head1 DESCRIPTION

This plugin is designed for downloading assets from a GitLab instance.

This is a cleaned and slightly extended local copy based on the original
work by Graham Ollis (plicease). The original distribution is available
on MetaCPAN and at L<https://github.com/PerlAlien/Alien-Build-Plugin-Download-GitLab>.

=head1 PROPERTIES

=head2 gitlab_host

The host to fetch from L<https://gitlab.com> by default.

=head2 gitlab_user

The user (or group) to fetch from. Required.

=head2 gitlab_project

The project to fetch from. Required.

=head2 type

The asset type to fetch. This must be one of C<source> or C<link>.
Default is C<source>.

=head2 format

The expected format of the asset. This should be one that
L<Alien::Build::Plugin::Extract::Negotiate> understands.
The default is C<tar.gz>.

=head2 version_from

Where to compute the version from. This should be one of
C<tag_name> or C<name>. The default is C<tag_name>.

=head2 convert_version

This is an optional code reference which can be used to modify
the version. For example, if tags have a C<v> prefix you could
remove it like so:

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

For C<link> types, this is a regular expression that filters the
asset filenames. For example, if there are multiple archive
formats provided, you can get just the gzip'd tarball by setting
this to C<qr/\.tar\.gz$/>.

=cut

has gitlab_host    => 'https://gitlab.com';
has gitlab_user    => undef;
has gitlab_project => undef;

has type => 'source';  # source or link

has format => 'tar.gz';

has version_from    => 'tag_name'; # tag_name or name
has convert_version => undef;
has link_name       => undef;

my $once = 1;

sub init
{
  my($self, $meta) = @_;

  croak("No gitlab_user provided")    unless defined $self->gitlab_user;
  croak("No gitlab_project provided") unless defined $self->gitlab_project;
  croak("Don't set a start_url with the Download::GitLab plugin")
    if defined $meta->prop->{start_url};

  $meta->add_requires('configure' => 'Alien::Build::Plugin::Download::GitLab' => 0);

  my $url = URI->new($self->gitlab_host);
  $url->path("/api/v4/projects/@{[ uri_escape(join '/', $self->gitlab_user, $self->gitlab_project) ]}/releases");
  $meta->prop->{start_url} ||= "$url";

  $meta->apply_plugin('Download');
  $meta->apply_plugin('Extract', format => $self->format);

  # We assume that GitLab returns the releases in reverse chronological order.
  $meta->register_hook(
    prefer => sub {
      my($build, $res) = @_;
      return $res;
    },
  );

  croak "type must be one of source or link"
    if $self->type !~ /^(source|link)$/;
  croak "version_from must be one of tag_name or name"
    if $self->version_from !~ /^(tag_name|name)$/;

  my %gl_fetch_options;
  my $secret;

  foreach my $name (qw( ALIEN_BUILD_GITLAB_TOKEN GITLAB_TOKEN GITLAB_PRIVATE_TOKEN ))
  {
    if (defined $ENV{$name})
    {
      $secret = $ENV{$name};
      push @{ $gl_fetch_options{http_headers} }, 'PRIVATE-TOKEN' => $secret;
      Alien::Build->log("using the GitLab Private Token in $name") if $once;
      $once = 0;
      last;
    }
  }

  $meta->around_hook(
    fetch => sub {
      my $orig = shift;
      my($build, $url, @the_rest) = @_;

      # Only modify the response / inject headers when we are talking to
      # the GitLab API endpoint that this plugin configured.
      # This avoids leaking the token to other hosts.
      my $start_url = $meta->prop->{start_url};
      my $is_gitlab_api = do {
        my $check = $url // $start_url;
        defined $check && $check eq $start_url;
      };

      return $orig->($build, $url, @the_rest)
        unless $is_gitlab_api;

      # Temporarily patch the log method so that we don't log the token
      my $log = \&Alien::Build::log;
      no warnings 'redefine';
      local *Alien::Build::log = sub {
        if (defined $secret)
        {
          $_[1] =~ s/\Q$secret\E/ '#' x length($secret) /eg;
        }
        goto &$log;
      };
      use warnings;

      my $res = $orig->($build, $url, @the_rest, %gl_fetch_options);

      my $res2 = {
        type => 'list',
        list => [],
      };

      $res2->{protocol} = $res->{protocol} if exists $res->{protocol};

      my $rel;
      if ($res->{content})
      {
        $rel = decode_json $res->{content};
      }
      elsif ($res->{path})
      {
        $rel = decode_json path($res->{path})->slurp_raw;
      }
      else
      {
        croak("malformed response object: no content or path");
      }

      foreach my $release (@$rel)
      {
        my $version = $self->version_from eq 'name'
          ? $release->{name}
          : $release->{tag_name};
        $version = $self->convert_version->($version) if $self->convert_version;

        if ($self->type eq 'source')
        {
          foreach my $source (@{ $release->{assets}->{sources} || [] })
          {
            next unless $source->{format} eq $self->format;
            my $src_url = URI->new($source->{url});
            my $filename = basename $src_url->path;
            push @{ $res2->{list} }, {
              filename => $filename,
              url      => $source->{url},
              version  => $version,
            };
          }
        }
        else # link
        {
          foreach my $link (@{ $release->{assets}->{links} || [] })
          {
            my $link_url = URI->new($link->{url});
            my $filename = basename $link_url->path;
            if ($self->link_name)
            {
              next unless $filename =~ $self->link_name;
            }
            push @{ $res2->{list} }, {
              filename => $filename,
              url      => $link->{url},
              version  => $version,
            };
          }
        }
      }

      return $res2;
    },
  );
}

1;

__END__

=head1 ENVIRONMENT

=over 4

=item ALIEN_BUILD_GITLAB_TOKEN, GITLAB_TOKEN, GITLAB_PRIVATE_TOKEN

If one of these environment variables is set, then the GitLab
Private Token (or Personal Access Token) will be used when
connecting to the GitLab API.

The header sent is:

  PRIVATE-TOKEN: <token>

For security reasons the token is redacted from the log. Some
Fetch plugins (for example the C<curl> plugin) will log HTTP
request headers; this ensures your token is not displayed.

=back

=head1 SEE ALSO

=over 4

=item L<Alien>

=item L<Alien::Build::Plugin::Download::GitHub>

=item L<alienfile>

=item L<Alien::Build>

=item L<https://github.com/PerlAlien/Alien-Build-Plugin-Download-GitLab> (original)

=back

=head1 AUTHOR

Original author: Graham Ollis <plicease@cpan.org>

This cleaned/extended local copy maintained for personal use.

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2022 by Graham Ollis.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
