use Object::Pad ':experimental(:all)';

package perldoc_pl;

class perldoc_pl : isa(Plack::Runner) : does(Adjust::Params);

use v5.44;

# use Adjust::Params;
use Frame::App::Perldoc;
use IO::Handle::Common;

field $instance : param //= Frame::App::Perldoc->new;
field $app  : param : reader { $instance->to_app };
field $argv : reader = \@ARGV;

ADJUST : params (:$argv) {
    $self->adjust_param(
        {
            \$self->argv => sub ($val) {
                shift @$val
                  if refstr($val) eq 'ARRAY' && $$val[0] && $$val[0] =~ /^--?$/;
            }
        }
    )
  }

  method run {
    dmsg $self;
    $self->parse_options(@$argv);
    Plack::Runner::run( $self, $app );
}

method cli : common ($argv //= \@ARGV) {
    my $perldoc = Frame::App::Perldoc->new;

    unless ( caller [2] ) {
        my $runner = $class->new(
            argv     => $argv,
            instance => $perldoc,
            app      => $perldoc->to_app
        );

        $runner->run;

        error "$! ($?)" if $? != 0;
        exit $?;
    }

    $perldoc->to_app;
}

perldoc_pl->cli( \@ARGV );
