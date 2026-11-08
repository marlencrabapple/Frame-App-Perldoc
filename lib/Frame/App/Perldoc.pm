use Object::Pad ':experimental(:all)';

package Frame::App::Perldoc;

our $VERSION = '0.01_02';

class Frame::App::Perldoc : isa(Frame)
  : does(Frame::App::Perldoc::plenv) : does(Frame::App::Perldoc::PodPerldoc);

use utf8;
use v5.44;

use Const::Fast;
use Path::Try;
use IO::Handle::Common;
use Text::Xslate;
use List::Util qw'uniq any all';
use Syntax::Keyword::Defer;
use URI::Escape 'uri_escape';
use JSON::MaybeXS;
use Digest::SHA;
use Syntax::Keyword::Dynamically;

field $req;
field $uribase;

field $versionlist : accessor = {};
field $modlist_ord            = [];
field $modlist : accessor     = {};
field $versionlist_ord        = [];

field $cachedir;
field $xs : reader = Text::Xslate->new( path => './view' );

ADJUST : params (%param) {
    $cachedir = path(
            $param{cachedir} // $ENV{CACHEDIR} // '._'
          . ( __PACKAGE__ =~ s/::/-/rg )
          . '-cache-'
          . Frame::Base::epoch
    );

    $cachedir->mkdir unless $cachedir->is_dir;
    $self->load_cache if path("$cachedir/modlist.json");

};

ADJUST {

    $self->load_installed_perl;
    dmsg $versionlist, $versionlist_ord
}

my method modinfo_clean ($modinfo) {

    my %modinfo =
      ( $modinfo->%{ grep { $_ !~ /perldoc|pod2html/ } keys $modinfo->%* } );

    $modinfo{file} = "$modinfo{file}" if $modinfo{file};

    $modinfo{cksum}{self} = Digest::SHA::sha256_hex(
        $self->json->encode(
            [ map { ( $_ => $modinfo{$_} ) } sort keys %modinfo ]
        )
    );

    \%modinfo;
}

method load_installed_perl {
    push @$versionlist_ord, $self->plenv->versions;

    %$versionlist = map {
        my ( $verstr, $text ) = ( $_ =~ /^[\s*]+([^\s]+)(\s.+)?$/g );
        $_ = $verstr;

        dynamically $ENV{PLENV_VERSION} = $verstr;

        $self->update_modlist( perlver => $verstr, update => 1 );

        ( $verstr => { prefix => $self->plenv->prefix } )
    } @$versionlist_ord;
}

method load_cache (%opt) {
    my $path = path("$cachedir/modlist.json");
    return undef unless $path->is_file;

    my $json = $self->json->decode( $path->slurp_utf8 );

    foreach my ( $pkgname, $modinfo ) (%$json) {
        $$modinfo{file} = path( $$modinfo{file} ) if $$modinfo{file};
        my $cachefile = path("$cachedir/$$modinfo{cksum}.html");
        next unless $cachefile->is_file;

        if ( my $htmlcache = $cachefile->slurp_utf8 ) {
            if ( $$modinfo{cksum} eq $htmlcache->digest ) {
                $$modinfo{modified} = $htmlcache->stat->mtime;
                $$modinfo{created}  = $htmlcache->stat->ctime;
                $$modinfo{htmlstr}  = $htmlcache->slurp_utf8;

            }
            else {
                $htmlcache->remove;
                error "HTML cache for $pkgname has an invalid checksum!\n"
                  . "(Expected: $$modinfo{cksum}\n"
                  . " Got: "
                  . $htmlcache->digest . ')';

                # dmsg $pkgname, $modinfo, $htmlcache;
            }

        }
    }
}

method update_module ( $pkgname, %opt ) {
    $self->get_module( $pkgname, update => true, %opt );
}

method get_module ( $name, %opt ) {
    ( $opt{update_html} = $opt{update_perldoc} ) //= $opt{write_html} //=
      $opt{update_html} //= $opt{update_perldoc} //= $opt{update} //=
      !$ENV{NO_CACHE} // false;

    my $modinfo = {};

    # const my $pkgname_dist_re => qr/([a-z0-9]+)(\-|::)?$/i;

    my @parts = split /(::|-|\/)/, $name;

    if ( all { /^[a-z0-9_]+$/ } (@parts) ) {
        $$modinfo{distname} = join '-',  @parts;
        $$modinfo{package}  = join '::', @parts;
    }

    $modinfo = { %$modinfo, ( $modlist->{ $$modinfo{distname} } // {} )->%* };

    if ( $opt{update_perldoc} || !$$modinfo{file} ) {
        my $perldoc = $self->perldoc->module( $$modinfo{distname}, %opt );

        if (
            !$perldoc->isa(
                'Frame::App::Perldoc::PodPerldoc::__LEXCLASS__/PodPerldoc')
          )
        {
            if ( $perldoc->isa('IPC::Nosh') ) {
                my $status = $perldoc->status;
                error "Failed to get perldoc for $$modinfo{package}"
                  . (
                    scalar $perldoc->err->lines_utf8
                    ? ": "
                      . ( join " ", $perldoc->err->lines_utf8 )
                      . "($status)"
                    : "\nExited with $status"
                  );

            }
            else {
                error
"Unknown error encountered trying to fetch perldoc for $$modinfo{package}";
            }

            return undef;
        }

        $modinfo = {
            %$modinfo,
            file  => $perldoc->file,
            cksum => { file => $perldoc->file->digest },

            # perldoc => $perldoc,
            url => "$ENV{SITE_URL}/$$modinfo{distname}"
        };
    }

    if (
        $opt{pod2html}
        && (
            $opt{update_html}
            || (  !$$modinfo{htmlstr}
                || $$modinfo{htmlstr} eq '' )
        )
      )
    {
        $modinfo = { %$modinfo, $self->html( $$modinfo{file} )->%* };

        $$modinfo{cksum}{html} =
          Digest::SHA::sha256_hex( delete $$modinfo{htmlstr} )
          if $$modinfo{htmlstr};
    }

    my $modified;

    if ( my $modinfo_curr = $$modlist{ $$modinfo{distname} } ) {
        my $modinfo_clean = modinfo_clean( $self, $modinfo );

        if (  !$$modinfo_curr{cksum}
            || $$modinfo_curr{cksum} ne $$modinfo_clean{cksum} )
        {
            $$modlist{ $$modinfo{distname} } = $modinfo
              if $opt{update_modlist}
              || ( !defined $opt{update_modlist} || $opt{update_modlist} );

            $modified = $modinfo_clean;
        }

    }
    else {
        $modified = modinfo_clean( $self, $modinfo );
        $$modlist{ $$modinfo{distname} } = $modinfo;
    }

    # dmsg $modified, \%opt;

    if ($modified) {
        $self->write_mod_cache( $$modinfo{distname}, update => 1 )
          if $opt{write_html};
        $self->write_cache_index if $opt{write_modlist};
    }

    $modinfo;
}

method update_modlist (%opt) {
    my $write_modlist = delete $opt{write_modlist} // 1;

    dynamically $ENV{PLENV_VERSION} = $opt{perlver};

    $self->update_module(
        $_,
        pod2html => $ENV{WARMUP_POD2HTML},
        ( $opt{update} ? ( update_modlist => 1 ) : () ),
        ( write_modlist => !$write_modlist ), %opt
      )
      for (

        $self->plenv->list_modules( $opt{perlver} ), map { path($_)->basename }
        map { ( $self->plenv->which( path($_)->basename ) ) }
        $self->plenv->shims
      );

    @$modlist_ord = sort keys %$modlist;

    $self->write_cache_index if $write_modlist;
}

method write_cache_index (%opt) {
    path("$cachedir/modlist.json")->spew_utf8(
        $self->json->encode(
            {
                map { ( $_ => modinfo_clean( $self, $$modlist{$_} ) ) }
                  keys %$modlist
            }
        )
    );
}

method write_mod_cache ( $distname, %opt ) {
    my $modinfo       = $$modlist{$distname};
    my $modinfo_clean = modinfo_clean( $self, $$modlist{$distname} );

    path("$cachedir/$$modinfo_clean{cksum}.html")
      ->spew_utf8( $$modinfo{htmlstr} )
      if $$modinfo{htmlstr};

}

method render( $template, $data, %opt ) {
    my $currperl = $xs->render(
        $template,
        {
            uribase  => $uribase,
            modlist  => [ $modlist->@{@$modlist_ord} ],
            currperl =>
              { $ENV{PLENV_VERSION} => $$versionlist{ $ENV{PLENV_VERSION} } },
            perllist => { $versionlist->%{@$versionlist_ord} },
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
            title => 'Module Index'
        }
    );

    $res->body($content);
    $res;
}

method perldoc_page( $tx, $name //= 'perl' ) {
    my $req = $tx->req;
    my $res = $req->new_response(200);

    my $modinfo = $self->update_module( $name, pod2html => 1 );
    $$modinfo{htmlstr} ||= $modinfo->{pod2html}{output_string}->$*;

    $res->status(200);

    my $body = $self->app->render(
        'module.tx',
        {
            %$modinfo, htmlstr => Text::Xslate::mark_raw( $$modinfo{htmlstr} )
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

    my %perlver_route = ();

    foreach my ( $ver, $info ) ( $versionlist->%{@$versionlist_ord} ) {
        $perlver_route{$ver} = $r->under(
            '/$ver',
            sub ( $c, @arg ) {
                dynamically $ENV{PLENV_VERSION} = $ver;
            }
        );
    }

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
            my $res = $app->perldoc_page( $self, $name );

            # if($res->status == 200) {
            #     $doc->get("/$name"
            # }

            $res;
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
