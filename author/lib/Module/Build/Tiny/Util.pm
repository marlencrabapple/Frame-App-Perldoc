package Module::Build::Tiny::Util;

use v5.40;

use Path::Tiny;
use Text::Xslate;
use IPC::Nosh;
use IO::Handle::Common;
use CPAN::Meta;
use File::XDG;

our $xs = Text::Xslate->new( syntax => 'Metakolon' );

sub version(%opt) {
    my $ver = $opt{ver} //= '0.01';
    $ver .= '-TRIAL' if $opt{trial} && $opt{trial} == 1;
    $ver;
}

sub generate_dist_config(%opt) {

}
