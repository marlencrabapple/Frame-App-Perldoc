use Object::Pad ':experimental(:all)';

package Frame::App::Perldoc::PodPerldoc;

role Frame::App::Perldoc::PodPerldoc : does(Frame::App::Perldoc::Base);

use v5.44;

use Pod::Simple::HTML;
use IO::Handle::Common;
use Path::Try;
use Syntax::Keyword::Try;
use Syntax::Keyword::Dynamically;

my class PodPerldoc {

    use Pod::Perldoc;
    use Path::Try;
    use IO::Handle::Common;
    use IPC::Nosh;
    use Syntax::Keyword::Try;

    field $file : reader : param;
    field $pod;
    field $poderr : reader : param;

    ADJUST {
        $file = path($file)->absolute;
        $pod  = $file->slurp_utf8;
    }

    method module : common ($name, %opt) {
        my $htmlstr;
        my $_perldoc;

        my @cmd    = ( qw'perldoc -T -u -l', $name );
        my $cmdstr = join " ", \@cmd;
        my $run    = run(
            \@cmd,
            autochomp => 1,
            out       => sub ( $line, @ ) {
                info("$cmdstr: $line [STDOUT]")
                  if ( $opt{debug} // $ENV{DEBUG} ) == 2;
            },
            err => sub ( $line, @ ) {
                error("$cmdstr: $line [STDERR]")
                  if ( $opt{debug} // $ENV{DEBUG} ) == 2;
            }
        );

        if ( $run->status > 0 ) {
            dmsg $run;
            return $run;
        }

        $class->new(
            module => $name,
            file   => path( ( $run->out->lines_utf8 )[0] )->absolute,
            poderr => [ $run->err->lines_utf8 ],
        );
    }
};

method perldoc {
    PodPerldoc;
}

method pod2html ( $file, %opt ) {
    my $pod2html = Pod::Simple::HTML->new;
    $pod2html->set_source( $file->openr_utf8 );

    $pod2html->perldoc_url_prefix( $opt{url_prefix}   // "/" );
    $pod2html->bare_output( $opt{bare_output}         // 1 );
    $pod2html->index( $opt{index}                     // 1 );
    $pod2html->complain_stderr( $opt{complain_stderr} // 1 );
    $pod2html;
}

method html ( $file, %opt ) {
    my %modinfo = ();
    $modinfo{htmlstr} = "";

    my $pod2html = $self->pod2html( path($file)->absolute );

    $pod2html->output_string( \$modinfo{htmlstr} );
    $pod2html->run;

    foreach my $meth (
        qw'get_author get_authors get_description get_short_title get_title get_title_short get_token get_version'
      )
    {
        my ($field) = ( $meth =~ s/get_//rg );
        $modinfo{$field} = $pod2html->$meth;
    }

    $modinfo{pod2html} = $pod2html;

    \%modinfo;
}
