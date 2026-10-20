use strict;
use warnings;
use Test::More;

my $loaded = eval { require Alien::Build::Plugin::Download::GitLab; 1 };
plan skip_all => "dependencies not installed: $@" unless $loaded;

my $pkg = 'Alien::Build::Plugin::Download::GitLab';

# Helpers under test are pure. A tiny stand-in avoids building a full
# alienfile just to check URL and candidate shaping. Call them as
# functions so this does not depend on the accessor generator.
package MockPlugin;
sub new { bless $_[1], $_[0] }
sub gitlab_host    { $_[0]->{gitlab_host} }
sub gitlab_user    { $_[0]->{gitlab_user} }
sub gitlab_project { $_[0]->{gitlab_project} }
sub type            { $_[0]->{type} }
sub format          { $_[0]->{format} }
sub version_from    { $_[0]->{version_from} }
sub convert_version { $_[0]->{convert_version} }
sub link_name       { $_[0]->{link_name} }

package main;

sub call { my $name = shift; $pkg->can($name)->(@_) }

my $plugin = MockPlugin->new({
  gitlab_host    => 'https://gitlab.example.com',
  gitlab_user    => 'group/sub',
  gitlab_project => 'proj',
  type           => 'source',
  format         => 'tar.gz',
  version_from   => 'tag_name',
  convert_version => undef,
  link_name      => undef,
});

my $index = call('_releases_url', $plugin);
like(
  $index,
  qr{^https://gitlab\.example\.com/api/v4/projects/group%2Fsub%2Fproj/releases\?},
  'project path keeps encoded slashes',
);
like($index, qr{(?:^|[?&])per_page=100(?:&|$)}, 'asks for the max page');
like($index, qr{(?:^|[?&])sort=desc(?:&|$)}, 'newest releases first');

ok(call('_same_endpoint', 'https://gitlab.example.com', $index), 'index is on the configured host');
ok(
  call(
    '_same_endpoint',
    'https://gitlab.example.com',
    'https://gitlab.example.com/group/sub/proj/-/archive/v1.2.3/proj-v1.2.3.tar.gz',
  ),
  'source archive on the same host gets the token',
);
ok(
  !call('_same_endpoint', 'https://gitlab.example.com', 'https://example.com/file.tar.gz'),
  'other hosts do not get the token',
);
ok(
  !call('_same_endpoint', 'https://gitlab.example.com', 'http://gitlab.example.com/file.tar.gz'),
  'scheme mismatch does not get the token',
);
ok(call('_is_release_index', $index, $index), 'exact index url is the release list');
ok(
  !call(
    '_is_release_index',
    $index,
    'https://gitlab.example.com/group/sub/proj/-/archive/v1/proj-v1.tar.gz',
  ),
  'archive url is not parsed as the release list',
);

my $releases = [
  {
    tag_name => 'v1.2.3',
    name     => 'Release 1.2.3',
    assets   => {
      sources => [
        { format => 'zip',    url => 'https://gitlab.example.com/a/proj-v1.2.3.zip' },
        { format => 'tar.gz', url => 'https://gitlab.example.com/a/proj-v1.2.3.tar.gz' },
      ],
      links => [
        { url => 'https://example.com/drops/proj-v1.2.3.tar.gz' },
        { url => 'https://gitlab.example.com/uploads/proj-v1.2.3.zip' },
      ],
    },
  },
  {
    tag_name => 'v1.0.0',
    assets   => {},
  },
  { tag_name => 'v0.9.0' },
];

my $sources = call('_candidates_from_releases', $plugin, $releases);
is(scalar @$sources, 1, 'only the matching source format is kept');
is($sources->[0]{filename}, 'proj-v1.2.3.tar.gz', 'filename is taken from the URL path');
is($sources->[0]{version}, 'v1.2.3', 'version comes from tag_name');
is($sources->[0]{url}, 'https://gitlab.example.com/a/proj-v1.2.3.tar.gz', 'source url is kept');

$plugin->{type} = 'link';
$plugin->{link_name} = qr/\.tar\.gz$/;
$plugin->{convert_version} = sub { my $v = shift; $v =~ s/^v//; $v };

my $links = call('_candidates_from_releases', $plugin, $releases);
is(scalar @$links, 1, 'link_name filters filenames');
is($links->[0]{filename}, 'proj-v1.2.3.tar.gz', 'link filename parsed with assignment, not a fat comma');
is($links->[0]{version}, '1.2.3', 'convert_version rewrites the tag');
ok($links->[0]{url} =~ m{^https://example\.com/}, 'external link is still listed, but not a token host');

$plugin->{version_from} = 'name';
$plugin->{convert_version} = undef;
$plugin->{link_name} = undef;
my $named = call('_candidates_from_releases', $plugin, $releases);
is($named->[0]{version}, 'Release 1.2.3', 'version_from name uses the release title');

is(call('_redact', 's3cret', 'token s3cret leaked'), 'token ###### leaked', 'token is redacted');
is(call('_redact', undef, 'plain'), 'plain', 'redact is a no-op without a token');

done_testing;
