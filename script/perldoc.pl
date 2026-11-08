#!/usr/bin/env perl
use Object::Pad ':experimental(:all)';

package perldoc_pl;

class perldoc_pl : isa(Plack::Runner) : does(Adjust::Params);

use utf8;
use v5.44;

use Plack::Runner;
use Frame::App::Perldoc;
use IO::Handle::Common;

field $instance : param //= Frame::App::Perldoc->new;
field $app : param : reader { $instance->to_app };
field $argv //= \@ARGV;

ADJUST : params (%param) {
    $self->adjust_param(
        \$argv,
        \%param,
        cb => sub ($val) {
            shift @$val
              if $$val[0] =~ /^--?$/;
            $val;
        },
    );
};

method run {
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
