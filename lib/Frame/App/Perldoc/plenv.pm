use Object::Pad ':experimental(:all)';

package Frame::App::Perldoc::plenv;
role Frame::App::Perldoc::plenv : does(Frame::App::Perldoc::Base);

use utf8;
use v5.44;

field $plenv;

my class plenv {
    use v5.44;

    use Const::Fast;
    use IPC::Nosh;
    use IO::Handle::Common;
    use List::Util 'any';

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

        return unless any { $cmd eq $_ } @commands;

        my @cmd    = ( 'plenv', $cmd, @arg );
        my $cmdstr = join ' ', @cmd;

        my $run = run(
            \@cmd,
            out => sub ( $line, @ ) {

                info("$cmdstr: $line [STDOUT]") if $debug == 2;
            },
            err => sub ( $line, @ ) {

                error("$cmdstr: $line [STDERR]") if $debug == 2;
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
