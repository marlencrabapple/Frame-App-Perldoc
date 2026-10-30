use Object::Pad ':experimental(:all)';

package Frame::App::Perldoc;

our $VERSION = '0.01_1';

class Frame::App::Perldoc : isa(Frame)
  : does(Frame::App::Perldoc::plenv);

use utf8;
use v5.44;

use Const::Fast;
use Path::Try;
use IO::Handle::Common;
use Text::Xslate;
use List::Util qw'uniq';
use Frame::App::Perldoc::PodPerldoc;

field $app { $self->app };
field $req;
field $html = {};
field $uribase;
field $xs : reader = Text::Xslate->new( path => './view' );
field $modlist_ord = [];
field $modlist;

ADJUST {
    dmsg $self
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

    foreach my ( $mod, $modinfo ) ( $modlist->%{@$modlist_ord} ) {
        my $perldoc;
        my $pod2html;
        my $htmlstr;

        const my $getmodinfo => sub ($mod) {
            $perldoc  = $self->perldoc->module($mod);
            $pod2html = $perldoc->html( dest => \$htmlstr );

            $modinfo //= {
                name     => $mod,
                podhtml  => $htmlstr,
                pod      => $perldoc->pod,
                perldoc  => $perldoc,
                pod2html => $pod2html

                # version => $pod2html->get_version
            };

            foreach my $meth (
                qw'get_author get_authors get_description get_short_title get_title get_title_short get_token get_version'
              )
            {
                my ($field) = ( $meth =~ s/get_//rg );
                $$modinfo{$field} = $pod2html->$meth;
            }

            dmsg $modinfo;

            %$modinfo;
        };

        # push , $mod;
        $$modlist{$mod} //=
          { $getmodinfo->($mod), url => $tx->req->script_name . "/$mod" };

        dmsg $$modlist{$mod};
    }

    $res->body(
        $app->render(
            'modlist.tx',
            {
                title   => 'Module Index',
                modlist => [ $modlist->@{@$modlist_ord} ]
            }
        )
    );
    $res;
}

method perldoc_page( $tx, $name //= 'perl' ) {
    my $req = $tx->req;
    my $res = $req->new_response(200);

    my $pod2html;    #= $self->perldoc->pod2html;

    if ( !$$html{$name} ) {
        $$html{$name} //= "";
        $pod2html =
          $self->perldoc->module($name)
          ->html( dest => \( $modlist->{$name}{podhtml} ) );
    }

    $res->status(200);

    my $body = $app->render(
        'module.tx',
        {
            $$modlist{$name}->%*,
            htmlstr => Text::Xslate::mark_raw( $modlist->{$name}{podhtml} )
        }
    );

    $res->body($body);
    $res;
}

method perl_index($tx) {
    $self->perldoc_page( $tx, 'perl' );
}

my class StaticSrv : isa(Plack::App::File) {
    use v5.44;

    use Path::Try;
    use IO::Handle::Common;

    field $req;

    method get_path ($path) {
        fatal "Request field is not an instance of Plack::Request"
          unless blessed($req) && $req->isa('Plack::Request');

        my $res = $req->new_response;

        if ( $path->is_file ) {
            $res->status(200);
            $res->body( $path->openr_utf8 );
        }
        else {
            $res->status(404);
            $res->body('404 - File not found');
        }

        $res->finalize;
    }

    method call ( $env, @arg ) {

        $req = Plack::Request->new($env);

        if ( my ($rel) =
            $req->path_info eq '/' ? '/' : ( $req->path_info =~ /^\/(.*)$/g ) )
        {
            my $path =
              path(
                "$$self{root}/" . ( $rel =~ /\/$/g ? 'index.html' : $rel ) );
            return $self->get_path($path);
        }

        Plack::App::File::call( $self, @_ );
    }
};

method startup {
    my $app = $self;
    my $r   = $self->routes;

    $r->get( '/s' => StaticSrv->new( root => './static' )->to_app );
    $r->get( '/s/bulma.min.css' =>
          StaticSrv->new( file => './bulma/css/bulma.min.css' )->to_app );
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
