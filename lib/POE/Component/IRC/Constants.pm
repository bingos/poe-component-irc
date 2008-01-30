package POE::Component::IRC::Constants;

require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(PCI_REFCOUNT_TAG BLOCKSIZE INCOMING_BLOCKSIZE DCC_TIMEOUT PRI_LOGIN PRI_HIGH PRI_NORMAL MSG_PRI MSG_TEXT CMD_PRI CMD_SUB);

use strict;
use warnings;
use vars qw($VERSION);

$VERSION = '0.01';

# The name of the reference count P::C::I keeps in client sessions.
use constant PCI_REFCOUNT_TAG => "P::C::I registered";

use constant BLOCKSIZE => 1024;           # Send DCC data in 1k chunks
use constant INCOMING_BLOCKSIZE => 10240; # 10k per DCC socket read
use constant DCC_TIMEOUT => 300;          # Five minutes for listening DCCs

# Message priorities.
use constant PRI_LOGIN  => 10; # PASS/NICK/USER messages must go first.
use constant PRI_HIGH   => 20; # KICK/MODE etc. is more important than chatter.
use constant PRI_NORMAL => 30; # Random chatter.

use constant MSG_PRI  => 0; # Queued message priority.
use constant MSG_TEXT => 1; # Queued message text.

# RCC: Since most of the commands are data driven, I have moved their
# event/handler maps here and added priorities for each data driven
# command.  The priorities determine message importance when messages
# are queued up.  Lower ones get sent first.

use constant CMD_PRI => 0; # Command priority.
use constant CMD_SUB => 1; # Command handler.

1;

=head1 NAME

POE::Component::IRC::Constants - Defines constants required by L<POE::Component::IRC|POE::Component::IRC>.

=head1 SYNOPSIS

  use POE::Component::IRC::Constants;

=head1 DESCRIPTION

POE::Component::IRC::Constants defines constants required by L<POE::Component::IRC|POE::Component::IRC> 
and derived sub-classes.

=head1 AUTHOR

Chris Williams <chris@bingosnet.co.uk>

=head1 SEE ALSO

L<POE::Component::IRC|POE::Component::IRC>
