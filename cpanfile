use utf8;
use v5.44;

use subs qw'requires recommends on';

requires 'perl', 'v5.44';
requires 'Const::Fast';

use Const::Fast;

sub distname ($pkgname) {
    const my $pkg2dist => qr/::/;
    ( $pkgname =~ s/$pkg2dist/-/rg );
}

const our %pinned => (
    CRABAPP => {
        'Path::Try'          => '0.01_03',
        'IO::Handle::Common' => '0.01_07',
        'IPC::Nosh'          => '0.01_04',
        'Adjust::Params'     => '0.01_06',
        'Frame'              => '0.01_08'
    }
);

foreach my ( $author, $modules ) (%pinned) {
    foreach my ( $name, $ver ) (%$modules) {
        requires $name, $ver,
          dist => "$author/" . distname($name) . "-$ver-TRIAL.tar.gz";
    }
}

requires 'Pod::Perldoc';
requires 'Pod::Simple';
requires 'Const::Fast';
requires 'TOML::Tiny';
requires 'JSON::MaybeXS';
requires 'URI::Escape';
requires 'Plack::Runner';

