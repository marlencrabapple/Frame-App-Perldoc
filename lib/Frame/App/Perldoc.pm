use Object::Pad ':experimental(:all)';

package Frame::App::Perldoc;

our $VERSION = '0.01_1';

class Frame::App::Perldoc : isa(Frame) : does(Frame::Base)
  : does(Frame::App::Perldoc::plenv) : does(Frame::App::Perldoc::PodPerldoc);

use utf8;
use v5.44;

use Const::Fast;
use Path::Try;
use IO::Handle::Common;
use Text::Xslate;
use List::Util qw'uniq';
use Syntax::Keyword::Defer;
use URI::Escape 'uri_escape';

field $req;
field $html = {};
field $uribase;
field $xs : reader        = Text::Xslate->new( path => './view' );
field $modlist_ord        = [];
field $modlist : accessor = {};

ADJUST {
    $self->update_modlist;
}

method update_module ( $pkgname, %opt ) {

    # my $perldoc;
    my $pod2html;

    # my $htmlstr;
    my $modinfo;

    # try {
    my $perldoc = $self->perldoc->module($pkgname);

    # }
    # catch ($e) {

    # };

    if (
        !$perldoc->isa(
            'Frame::App::Perldoc::PodPerldoc::__LEXCLASS__/PodPerldoc')
      )
    {
        if ( $perldoc->isa('IPC::Nosh') ) {
            error "Failed to get perldoc for $pkgname: " . join " ",
              $perldoc->err->lines_utf8;

        }
        else {
            dmsg $perldoc;
            error
              "Unknown error encountered trying to fetch perldoc for $pkgname";
        }

        return undef;
    }

    $modinfo = {
        name => $pkgname,

        # podhtml => $htmlstr,

        # pod      => $perldoc->pod,
        file    => $perldoc->file,
        perldoc => $perldoc,

        # pod2html => $pod2html
        url => "$ENV{SITE_URL}/" . uri_escape("$pkgname")
    };

    if ( $opt{pod2html} ) {

        $$modinfo{htmlstr} //= "";
        $modinfo = {
            %$modinfo,
            $self->html( $perldoc->file, dest => \$$modinfo{htmlstr} )->%*
        };
    }

    $$modlist{$pkgname} = $modinfo;
    $modinfo;
}

method update_modlist (%opt) {
    $self->update_module( $_, pod2html => $ENV{WARMUP_POD2HTML} )
      for $self->plenv->list_modules;
    @$modlist_ord = sort keys %$modlist;
}

method render( $template, $data, %opt ) {
    $xs->render(
        $template,
        {
            uribase => $uribase,
            %$data
        }
    );
}

method req {
    $req || fatal "Transaction life cycle not yet started.";
}

method modlist_page ($tx) {
    my $res = $tx->req->new_response(200);

    my $content = $self->app->render(
        'modlist.tx',
        {
            title   => 'Module Index',
            modlist => [ $modlist->@{@$modlist_ord} ]
        }
    );

    $res->body($content);
    $res;
}

method perldoc_page( $tx, $name //= 'perl' ) {
    my $req = $tx->req;
    my $res = $req->new_response(200);

    if ( !$$modlist{$name} ) {
        my $perlmod = $self->update_module($name);
    }

    $modlist->{$name}{htmlstr} //= "";

    my $modinfo = $self->html( $$modlist{$name}{perldoc}->file,
        dest => \$$modlist{$name}{htmlstr} );

    $res->status(200);

    my $body = $self->app->render(
        'module.tx',
        {
            $$modlist{$name}->%*,
            htmlstr => Text::Xslate::mark_raw( $$modlist{name}{htmlstr} )
        }
    );

    $res->body($body);
    $res;
}

method perl_index($tx) {
    $self->perldoc_page( $tx, 'perl' );
}

my class StaticSrv : isa(Plack::App::File) : does(Adjust::Params) {
    use v5.44;

    use Path::Try;
    use IO::Handle::Common;

    field $req  : reader;
    field $file : accessor //= undef;
    field $root : accessor //= path('./');

    ADJUST : params (%param) {
        $self->adjust_params(
            [ \$file, \$root ],
            \%param,
            cb => sub ($val) {
                path($val)->absolute if $val;
            }
        );
    };

    method get_path ($path) {
        fatal "Request field is not an instance of Plack::Request"
          unless blessed($req) && $req->isa('Plack::Request');

        my $res = $req->new_response;

        if ( $path->is_file ) {
            $res->status(200);
            $res->body( $path->openr_raw );
        }
        else {
            $res->status(404);
            $res->body('404 - File not found');
        }

        $res;
    }

    method map_path ($path_info) {

        # dmsg $self, $path_info, $root, $file, $req;
        if ($root) {
            if (
                my ($rel) =
                $path_info eq '/'
                ? '/'
                : ( $path_info =~ /^\/(.*)$/g )
              )
            {
                my $path =
                  path( ( $rel =~ /\/$/g ? 'index.html' : $rel ) )
                  ->relative($root);

                return $self->get_path($path);
            }
        }
        else {
            return $self->get_path( $file->absolute ) if $file;
        }
    }

    method to_route {

        sub ( $c, $path //= $c->req->path_info, @arg ) {

            # dmsg $c->req->env, $path, \@arg;
            $req = $c->req;
            $self->get_path( $self->map_path($path) );

            # $self->call( $c->env, @arg );
        }
    }

    method call ( $env, @arg ) {
        $req = Plack::Request->new($env);
        $self->get_path( $self->map_path( $req->path_info ) );
        Plack::App::File::call( $self, $env, @arg );
    }
};

method startup {
    my $r   = $self->routes;
    my $app = $self->app;

    $r->get( '/s/:path' => StaticSrv->new( root => './static' )->to_route );
    $r->get(
        '/s/bulma.min.css' => sub ( $c, @arg ) {
            const my $static =>
              StaticSrv->new( file => './inc/bulma/css/bulma.min.css' );

            my $res = $c->req->new_response;
            $res->status(200);
            $res->body( $static->file->openr_raw );
            $res;
        }
    );

    $r->get(
        'favicon.ico' => sub ( $c, @arg ) {
            const my $static =>
              StaticSrv->new( file => './static/favicon.ico' );

            my $res = $c->req->new_response;
            $res->status(200);
            $res->body( $static->file->openr_raw );
            $res;
        }
    );

    my $doc = $r->under(
        '/' => sub ( $self, @arg ) {
            $uribase = $self->req->script_name;
            return $app->perl_index($self) if $self->req->path_info eq '/';
            1;
        }
    );

    $doc->get(
        '/modlist' => sub ($self) {
            $app->modlist_page($self);
        }
    );

    $doc->get(
        '/:name' => sub ( $self, $name //= 'perl' ) {
            $app->perldoc_page( $self, $name );
        }
    );

    $self;
}

=encoding utf-8

=head1 NAME

Frame::App::Perldoc - Blah blah blah

=head1 SYNOPSIS

  use Frame::App::Perldoc;

=head1 DESCRIPTION

Frame::App::Perldoc is

=head1 AUTHOR

Ian P Bradley E<lt>ian@pennyfoss.orgE<gt>

=head1 COPYRIGHT

Copyright 2026- Ian P Bradley

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut
