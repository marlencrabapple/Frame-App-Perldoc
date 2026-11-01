#!/usr/bin/env perl
package dist;

use v5.40;
no warnings 'experimental::re_strict';
use re 'strict';

use Path::Tiny;
use Const::Fast;
use TOML::Tiny qw'from_toml to_toml';
use CPAN::Mini::Inject;
use IPC::Nosh;
use Syntax::Keyword::Defer;
use Syntax::Keyword::Try;
use IO::Handle::Common;
use Getopt::Long
  qw(GetOptionsFromArray :config no_ignore_case auto_abbrev passthrough bundling long_prefix_pattern=--?);

const our $toml => TOML::Tiny->new;

our $verbose = $ENV{VERBOSE} // 9;
our $debug   = $ENV{DEBUG}   // 0;

our %config_path = ( author => path('minil.toml') );
our %config = ( author => $toml->decode( $config_path{author}->slurp_utf8 ) );

my $package = ( $config{author}->{name} =~ s/-/::/gr );
my $archive;
my $version;

my $trial //= $config{author}->{release_status}
  && $config{author}->{release_status} ne 'stable' ? 1 : 0;

my $has_suffix;

const our $dist_suffix_default => 'TRIAL';
my $dist_suffix;
$dist_suffix = $dist_suffix_default if $trial;

sub cli ( $argv = \@ARGV, %opt ) {

    GetOptionsFromArray(
        $argv,
        'trial' => \$trial,
        'verbose+',
        => \$verbose,
        'debug+',
        => \$debug,
        'quiet' => sub {
            $verbose = 0;
        }
    );

    $dist_suffix //= $dist_suffix_default if $trial;
}

sub mvdir ( $src, $dst, %opt ) {
    $dst->mkdir unless $dst->is_dir;

    my $onvisit = sub ( $path, $state ) {

        if ( $path->is_dir ) {
            $dst->mkdir($path);
            $path->remove_tree if scalar $path->children == 0;
            return;
        }
        else {
            $path->copy($dst);
            $path->remove;
        }
    };

    $src->visit( $onvisit, { recurse => 1 } );
    $src->remove_tree;
}

sub make_dist( $dist, %opt ) {
    my ( $archive, $version, $has_suffix );
    my $test = 0;

    my $bindir = path('./bin');
    my $tmp;

    if ( $bindir->is_dir ) {
        info
"Temporarily relocating './bin' from the build root to avoid conflict with authorship/build scripts";

        $tmp = Path::Tiny->tempdir;

        mvdir( $bindir, $tmp );

    }

    const my $archive_re => qr/^Wrote (($dist)-(.+?)(?:-(TRIAL))?\.tar\.gz)$/;

    my $run = run(
        [qw'minil dist'],
        out => sub ( $line, @ ) {
            $test++;

            if ($verbose) {
                my $say = $debug ? __LINE__ . ": $line" : $line;
                say $say;
            }

            # TODO: Add functionality to remove callback when no longer needed
            ( $archive, undef, $version, $has_suffix ) =
              ( $line =~ $archive_re )
              unless $archive && $version;
        },
        err       => sub ( $line, @ ) { say STDERR $line if $verbose },
        autochomp => 1
    );

    mvdir( $tmp, $bindir ) if $tmp;

    dmsg $run, $archive, $version, $has_suffix, $test;

    say join "\n", $run->err->lines_utf8 if $verbose;

    fatal( ( join " ", $run->cmd->@* )
        . " exited with non-zero status: "
          . $run->status )
      if $run->status != 0;

    fatal "Could not parse archive name from '"
      . ( join " ", $run->cmd->@* )
      . "' output."
      unless $archive && $version;

    ( $archive, $version, $has_suffix );
}

sub make_build () {

}

sub rename_archive ( $src, $dst ) {
    $archive->move($dst);
}

sub upload_to_cpanm {
    ...;
}

sub dist {

    ( $archive, $version, $has_suffix ) =
      make_dist( $config{author}->{name}, trial => $trial );

    # dmsg( $archive, $version, $has_suffix );

    $archive = path($archive);

    if (
        my $moved =
          $has_suffix || !$dist_suffix
        ? $archive
        : rename_archive(
            $archive,
            $archive->basename(qr/\.tar\.gz$/) . "-$dist_suffix.tar.gz"
        )
      )
    {
        success "Wrote $moved";
        exit 0;
    }
    else {
        fatal "Something went wrong. ($?)";
        dmsg $archive, $moved;
    }
}

cli( \@ARGV );
dist()
