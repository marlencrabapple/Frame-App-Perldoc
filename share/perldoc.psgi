use Object::Pad ':experimental(:all)';

package Frame::App::perldoc::mcpani;
role Frame::App::perldoc::mcpani;

use utf8;
use v5.44;

my class mcpani : does(Frame::Base) {

    use v5.44;

    use Path::Try;
    use File::HomeDir;
    use Const::Fast;
    use List::Util qw'all any pairgrep';
    use IO::Handle::Common;
    use builtin;

    const our $splitle_re => qr/[\n\r]+/;

    field $userhome : param = File::HomeDir->my_home;
    field $config : reader : param = {};
    field $modlist { $self->modlist };

    ADJUST : params (:$config_file = "$userhome/.mcpani/config") {
        dmsg $config_file;
        $config = {
            __PACKAGE__->parse_config(
                [ path($config_file)->absolute->lines_utf8 ]
            )
        };
        dmsg $config;
    };

    method parse_config : common (@in) {
        const my $lines_aref => sub($str) {
            [ split /$splitle_re/, $str ]
        };

        my $in =
          scalar @in == 1
          && ( any { Frame::Base::refstr( $in[0] ) eq $_ } ( 'ARRAY', '' ) )
          ? shift @in
          : \@in;

        if ( my $type = reftype $in ) {
            if ( $type ne 'ARRAY' ) {
                $in = $lines_aref->("$in");
            }
        }
        else {
            $in = $lines_aref->($in);
        }

        my %config;

        foreach my ( $k, $v ) ( map { (/^([^\s:]+)\s*:\s(.+)$/g) } @$in ) {
            $v = builtin::trim($v);
            dmsg $k, $v;
            next unless all { $_ && $_ ne '' } ( $k, $v );

            my @v = split /\s/, $v;
            $v = \@v if scalar @v > 1;

            $config{$k} = $v;
        }

        %config;
    }

    method modlist {
        if ( !$$config{local} ) {
            dmsg $self, $config;
            return undef;
        }
        my $path = path( $$config{local} );
        dmsg $self, $config;
        my @modlist;

        #         my $visit = path( $$config{local} )->visit(

        #             sub ( $path, $state ) {
        #                 return
        #                   unless $path->is_file;

        #                 my %diststub;

        #                 ( @diststub{qw'name version suffix'} ) =
        #                   ( $path->basename =~
        # /^([a-z90-9_-]+)-([a-z0-9._]+)(?:-([a-z0-9_]+))?.tar.gz$/ig
        #                   );

        #                 dmsg \%diststub;

        #                 push @modlist, \%diststub;
        #             },
        #             { recurse => 1 }
        #         );
    }
};

method mcpani {
    state $mcpani //= mcpani->new;
    $mcpani;
}

package Frame::App::perldoc::plenv;
role Frame::App::perldoc::plenv;

use utf8;
use v5.44;

field $plenv;

my class plenv {
    use v5.44;

    use Const::Fast;
    use IPC::Nosh;
    use IO::Handle::Common;

    use vars qw'@commands';

    field $debug : param = $ENV{DEBUG} // 0;

    BEGIN {
        my $run = run(
            [qw'plenv commands'],
            out => sub ( $line, %opt ) {

                # const my $dev_null = IO::Handle->
                # error join " ", @opt{cmd} . ": $line"
                # ...;
            },
            autochomp => 1
        );
        const our @commands => ( $run->out->lines_utf8 );
    }

    field $commands = \@commands;

    method AUTOLOAD (@arg) {
        our $AUTOLOAD;

        my ( $class, $meth ) = ( $AUTOLOAD =~ /^(.*)::(.+)$/ );
        my $cmd = ( $meth =~ s/_/-/gr );

        my @cmd    = ( 'plenv', $cmd, @arg );
        my $cmdstr = join ' ', @cmd;

        my $run = run(
            \@cmd,
            out => sub ( $line, @ ) {

                info("$cmdstr: $line [STDOUT]") if $debug;
            },
            err => sub ( $line, @ ) {

                error("$cmdstr: $line [STDERR]") if $debug;
            },
            autochomp => 1
        );

        $run->out->lines_utf8;
    }
};

method plenv {
    state $plenv //= plenv->new;
    $plenv;
}

package Frame::App::perldoc::Base;
role Frame::App::perldoc::Base : does(Frame::Base);

#field $perldoc;




package perldoc_psgi;

class perldoc_psgi;

use utf8;
use v5.44;

use IO::Handle::Common;
use Plack::Builder;
use Path::Try;
use Plack::App::File;
use Frame::App::Perldoc;



builder {
    mount '/s/' => StaticSrv->new( root => './static' )->to_app;
    mount '/s/bulma.min.css' =>
      StaticSrv->new( file => './bulma/css/bulma.min.css' )->to_app;

    mount '/' => Frame::App::perldoc->new->to_app;
}

