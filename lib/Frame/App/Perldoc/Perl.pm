use Object::Pad ':experimental(:all)';

package Frame::App::Perldoc::Perl;

class Frame::App::Perldoc::Perl : does(Frame::App::Perldoc::Base) :
  does(Frame::App::Perldoc::plenv) : does(Frame::App::Perldoc::PodPerldoc);

use utf8;
use v5.44;

use Syntax::Keyword::Dynamically;

field $version : reader : param;
field $prefix  { $self->plenv->prefix };
field $modlist { $self->update_modlist };
field $binlist { $self->update_binlist };
field $app;

ADJUST {
    # $prefix
};

method update_binlist ( $perlver = $ENV{PLENV_VERSION}, %opt ) {
    $self->updlist( $self->plenv->shims, perlver => $perlver );
}

method update_modlist ( $perlver = $ENV{PLENV_VERSION}, %opt ) {
    $self->updlist( $self->plenv->list_modules, perlver => $perlver );
}

method updlist ( $in, %opt ) {
    my $write_modlist = delete $opt{write_modlist} // 1;

    $self->update_module(
        $_,
        pod2html => $ENV{WARMUP_POD2HTML},
        ( $opt{update} ? ( update_modlist => 1 ) : () ),
        ( write_modlist => !$write_modlist ), %opt
    ) for @$in;

    $modlist = hash( $modlist->%{ sort keys %$modlist }, order => 1 );

    $self->write_cache_index if $write_modlist;
}

# method plenv : override {
#     dynamically $ENV{PLACK_VERSION} = $version;
# }
#
