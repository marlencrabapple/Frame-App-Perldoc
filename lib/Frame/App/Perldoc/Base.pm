use Object::Pad ':experimental(:all)';

package Frame::App::Perldoc::Base;
role Frame::App::Perldoc::Base : does(Frame::Util) : does(Frame::Base);

use utf8;
use v5.44;

use Path::Try;
use IO::Handle::Common;
use IPC::Nosh;

use vars qw'@EXPORT';

@EXPORT = qw'epoch dmsg hash';

APPLY($class_mop) {
    Frame::Base->apply($class_mop)
};

ADJUST {
    $self->import;
};

my class Hash {
    field $keys_ord = [];
    field $data     = {};

    field $order : param //= 1;

    ADJUST : params (%kv) {
        foreach my ( $k, $v ) (%kv) {
            push @$keys_ord, $k if $order;
            $$data{$k} = $v;
        }
    };

    method kv {
        $order ? $data->%{@$keys_ord} : %$data;
    }

    method k {
        $order ? @$keys_ord : keys %$data;
    }

    method v {
        $order ? $data->@{@$keys_ord} : values %$data;
    }
};

use experimental 'signatures';
no warnings 'experimental::signature_named_parameters';

sub hash ( : $order, %param ) {
    Hash->new(%param);
}
