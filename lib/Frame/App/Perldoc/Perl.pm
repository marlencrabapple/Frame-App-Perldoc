use Object::Pad ':experimental(:all)';

package Frame::App::Perldoc::Perl;

class Frame::App::Perldoc::Perl : does(Frame::App::Perldoc::Base) :
  does(Frame::App::Perldoc::plenv) : does(Frame::App::Perldoc::PodPerldoc);

use utf8;
use v5.44;

use Path::Try;
use Syntax::Keyword::Dynamically;
use Const::Fast;

const our $modname_sep => qr/\-|::|\//;
const our $modname_ptn => qr/([a-z0-9]+)($modname_sep)?$/i;

field $version : reader : param;
field $prefix  { $self->plenv->prefix };
field $modlist { $self->update_modlist };
field $binlist { $self->update_binlist };
field $app;

my class PerlModule : does(Frame::App::Perldoc::Base) {
    use utf8;
    use v5.44;

    use Module::Info;
    use Path::Try;
    use Syntax::Keyword::Dynamically;
    use List::Util qw'first all';

    # Don't duplicate much package info, only what we use to identify it
    field $path;
    field $package;
    field $distname;
    field $author;

    field $meta;

    field $html;
    field $htmldigest;
    field $uri;

    ADJUST : params (:$path) {...};

    ADJUST : params (:$module, :$author) {

        my @parts = split /$modname_sep/, $module;

        if ( all { $_ =~ $modname_ptn } (@parts) ) {
            $distname = join '-',  @parts;
            $package  = join '::', @parts;
        }

        dmsg( $module, $author, $distname, $package )
    };

};

ADJUST {
    # $prefix
};

method module ($module) {

    # my $module = {};
    # my ( $pkgname, $dist );

    # if ( ) {
    #     $dist    = join '-',  @parts;
    #     $pkgname = join '::', @parts;
    # }

    # my $module =
    #   PerlModule->new( module => ($$modlist{$module});

    ( map { ( $_ => PerlModule->new( module => $$modlist{$_} ) ) }
          ARRAY($module) );

}

method update_binlist ( $perlver = $ENV{PLENV_VERSION}, %opt ) {
    $self->updlist(
        map { $self->plenv->which( path( $_->basename ) ) } $self->plenv->shims,
        perlver => $perlver
    );
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
