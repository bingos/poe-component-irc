# Declare our package
package POE::Component::Server::IRC::Plugin;

# Standard stuff to catch errors
use strict qw(subs vars refs);				# Make sure we can't mess up
use warnings FATAL => 'all';				# Enable warnings to catch errors

# Initialize our version
our $VERSION = '1.20';

# We export some stuff
require Exporter;
our @ISA = qw( Exporter );
our %EXPORT_TAGS = ( 'ALL' => [ qw( PCSI_EAT_NONE PCSI_EAT_CLIENT PCSI_EAT_PLUGIN PCSI_EAT_ALL ) ] );
Exporter::export_ok_tags( 'ALL' );

# Our constants
use constant PCSI_EAT_NONE   => 1;
use constant PCSI_EAT_CLIENT => 2;
use constant PCSI_EAT_PLUGIN => 3;
use constant PCSI_EAT_ALL    => 4;

1;
__END__
