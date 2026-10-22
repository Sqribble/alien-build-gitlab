use strict;
use warnings;
use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
  NAME             => 'Alien::Build::Plugin::Download::GitLab',
  AUTHOR           => 'Daniel Roberts <gimpybot@gmail.com>',
  VERSION_FROM     => 'lib/Alien/Build/Plugin/Download/GitLab.pm',
  ABSOLUTE         => 1,
  LICENSE          => ['Artistic-2.0', 'GPL-1.0-or-later'],
  MIN_PERL_VERSION => '5.008004',
  CONFIGURE_REQUIRES => {
    'ExtUtils::MakeMaker' => '6.52'
  },
  BUILD_REQUIRES => {
  },
  TEST_REQUIRES => {
    'Test2::V0' => '0.000060'
  },
  PREREQ_PM => {
    'Alien::Build::Plugin' => '0.25',
    'URI'                 => '0',
    'URI::Escape'         => '0',
    'JSON::PP'            => '0',
    'File::basename'      => '0',
    'Path::Tiny'          => '0.076'
  },
  META_MERGE => {
    'meta-spec' => { version => 2 },
    resources => {
      repository => {
        type => 'git',
        url  => 'https://github.com/Sqribble/alien-build-gitlab.git',
        web  => 'https://github.com/Sqribble/alien-build-gitlab'
      },
      bugtracker => {
        web => 'https://github.com/Sqribble/alien-build-gitlab/issues'
      }
    },
    x_contributors => [
      'Graham Ollis <plicease@cpan.org> (original author)'
    ]
  },
  dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz' },
  clean => { FILES => 'Alien-Build-Plugin-Download-GitLab-*' }
);

WriteMakefile(%WriteMakefileArgs);
