use Object::Pad ':experimental(:all)';

package Frame::App::Perldoc::PodPerldoc;

class Frame::App::Perldoc::PodPerldoc : does(Frame::App::Perldoc::Base);

use v5.44;

use Pod::Perldoc;
use Pod::Simple::HTML;
use IO::Handle::Common;
use Capture::Tiny qw'capture';
use Syntax::Keyword::Try;
use Syntax::Keyword::Dynamically;

field $pod2html;
field $pod     : reader : param;
field $poderr  : reader : param;
field $podret  : reader : param;
field $perldoc : reader : param;

ADJUST {
    $pod2html = $self->pod2html;
};

method pod2html (%opt) {
    dynamically $pod2html = Pod::Simple::HTML->new
      if $opt{new} || !$pod2html;
    $pod2html->perldoc_url_prefix( $opt{url_prefix}   // "/" );
    $pod2html->bare_output( $opt{bare_output}         // 1 );
    $pod2html->index( $opt{index}                     // 1 );
    $pod2html->complain_stderr( $opt{complain_stderr} // 1 );
    $pod2html;
}

method html (%opt) {
    my $dest = "";
    $opt{dest} //= \$dest;
    $pod2html->output_string( $opt{dest} );
    $pod2html->set_source( \$pod );
    $pod2html->run;
    $opt{dest} == \$dest ? $dest : $pod2html;
}

method module : common ($name) {
    my $htmlstr;
    my $_perldoc;

    my ( $stdout, $stderr, @ret ) = capture sub {
        try {
            local @ARGV = ( qw'-T -u', $name );
            $_perldoc = Pod::Perldoc->run;
        }
        catch ($e) {
            error $e;
        }
    };

    $class->new(
        module  => $name,
        pod     => $stdout,
        poderr  => $stderr,
        podret  => \@ret,
        perldoc => $_perldoc
    );
}
