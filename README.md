# Alien::Build::Plugin::Download::GitLab

Alien::Build plugin to download release assets from a GitLab instance.

This is a **cleaned and slightly extended local copy** of the original module by Graham Ollis (plicease).

- Original on MetaCPAN: [Alien::Build::Plugin::Download::GitLab](https://metacpan.org/pod/Alien::Build::Plugin::Download::GitLab)
- Original GitHub: [PerlAlien/Alien-Build-Plugin-Download-GitLab](https://github.com/PerlAlien/Alien-Build-Plugin-Download-GitLab)

## Changes in this copy

- Fixed a small syntax error present in the upstream source (`my $filename =>` → `=`).
- Added optional GitLab Private Token support via environment variables:
  - `ALIEN_BUILD_GITLAB_TOKEN`
  - `GITLAB_TOKEN`
  - `GITLAB_PRIVATE_TOKEN`
- Token is redacted from Alien::Build logs for safety.
- Minor robustness improvements (defensive `|| []` on asset arrays).
- Version bumped to 0.02 for this local edition.

## Synopsis

```perl
use alienfile;

share {
  plugin 'Download::GitLab' => (
    gitlab_user    => 'your-user-or-group',
    gitlab_project => 'your-project',
    # optional:
    # type           => 'source',   # or 'link'
    # format         => 'tar.gz',
    # version_from   => 'tag_name', # or 'name'
    # link_name      => qr/\.tar\.gz$/,
    # convert_version => sub { my $v = shift; $v =~ s/^v//; $v },
  );
};
```

## Installation (local / development)

```bash
# From the directory that contains the lib/ folder
export PERL5LIB=$PWD/lib:$PERL5LIB
```

Or install with `cpanm` / `cpan` after packaging.

## Environment Variables for Private Projects

```bash
export ALIEN_BUILD_GITLAB_TOKEN="glpat-xxxxxxxxxxxxxxxxxxxx"
# or
export GITLAB_TOKEN="glpat-xxxxxxxxxxxxxxxxxxxx"
# or
export GITLAB_PRIVATE_TOKEN="glpat-xxxxxxxxxxxxxxxxxxxx"
```

## License

Same terms as Perl 5 itself. Copyright (c) 2022 Graham Ollis.

## Author

- Original: Graham Ollis <plicease@cpan.org>
- This cleaned local copy: maintained under Sqribble for personal / experimental use.
