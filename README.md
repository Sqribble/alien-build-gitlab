# Alien::Build::Plugin::Download::GitLab

Alien::Build plugin that downloads a release archive from a GitLab instance.

Cleaned personal edition of the original module by Graham Ollis (plicease).

- Original on MetaCPAN: [Alien::Build::Plugin::Download::GitLab](https://metacpan.org/pod/Alien::Build::Plugin::Download::GitLab)
- Original source: [PerlAlien/Alien-Build-Plugin-Download-GitLab](https://github.com/PerlAlien/Alien-Build-Plugin-Download-GitLab)

## What was cleaned up

The upstream 0.01 sources do not compile in the `link` branch (`my $filename =>` is a syntax error), leave a `PRIVATE-TOKEN` TODO unimplemented, and crash when a release has no `assets` list. This tree fixes those and keeps the original license.

- Syntax error in the link-asset branch is fixed.
- Private-token support via `ALIEN_BUILD_GITLAB_TOKEN`, `GITLAB_TOKEN`, or `GITLAB_PRIVATE_TOKEN`.
- The token is sent only to the configured GitLab host (scheme, host, and port). It is not attached to links on other hosts, and it is redacted from Alien::Build logs.
- Same-host source archives receive the token, so private projects can actually download.
- Missing `assets` / `sources` / `links` lists are skipped instead of throwing.
- A GitLab error object (`{"message":"401 Unauthorized"}`) becomes a clear exception.
- The releases index asks for the newest 100 (`per_page=100`, `sort=desc`).
- Typo `Don't set set a start_url` is corrected.
- Version of this edition: 0.03.

## Synopsis

```perl
use alienfile;

share {
  plugin 'Download::GitLab' => (
    gitlab_user    => 'group/subgroup',
    gitlab_project => 'your-project',
    # optional:
    # gitlab_host  => 'https://gitlab.example.com',
    # type         => 'source',     # or 'link'
    # format       => 'tar.gz',     # tar.bz2, tar, zip
    # version_from => 'tag_name',   # or 'name'
    # link_name    => qr/\.tar\.gz$/,
    # convert_version => sub { my $v = shift; $v =~ s/^v//; $v },
  );
};
```

Put this checkout in front of the CPAN 0.01 release. `alienfile` requires version 0.03, so the broken upload cannot satisfy it:

```bash
export PERL5LIB="$PWD/lib:$PERL5LIB"
```

## Private projects

```bash
export ALIEN_BUILD_GITLAB_TOKEN="glpat-xxxxxxxxxxxxxxxxxxxx"
```

`GITLAB_TOKEN` and `GITLAB_PRIVATE_TOKEN` are also accepted. The first one that is set and non-empty wins. The header is `PRIVATE-TOKEN`.

## License

Same terms as Perl 5 itself. Copyright (c) 2022 Graham Ollis.

## Author

- Original: Graham Ollis <plicease@cpan.org>
- This cleaned edition: Sqribble
