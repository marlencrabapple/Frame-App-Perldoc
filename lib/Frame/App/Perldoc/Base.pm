use Object::Pad ':experimental(:all)';

package Frame::App::Perldoc::Base;
role Frame::App::Perldoc::Base : does(Frame::Base) : does(Adjust::Params);

use utf8;
use v5.44;

use Path::Try;
use IO::Handle::Common;
use IPC::Nosh;

use parent 'Exporter';

