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
=head1 NAME

POE::Component::Server::IRC::Plugin - Provides plugin documentation for POE::Component::Server::IRC.

=head1 ABSTRACT

	Provides plugin documentation for POE::Component::Server::IRC

=head1 DESCRIPTION

This is the document coders/users should refer to when using/developing plugins for
POE::Component::Server::IRC.

The plugin system works by letting coders hook into aspects of POE::Component::Server::IRC::Backend:

	Data received from the server

The general architecture of using the plugins should be:

	# Import the stuff...
	use POE;
	use POE::Component::Server::IRC::Backend;
	use POE::Component::Server::IRC::Plugin::ExamplePlugin;

	# Create our session here
	POE::Session->create( ... );

	# Create the IRC session here
	my $irc = POE::Component::Server::IRC::Backend->spawn() or die 'Nooo!';

	# Create the plugin
	# Of course it could be something like $plugin = MyPlugin->new();
	my $plugin = POE::Component::Server::IRC::Plugin::ExamplePlugin->new( ... );

	# Hook it up!
	$irc->plugin_add( 'ExamplePlugin', $plugin );

	# OOPS, we lost the plugin object!
	my $pluginobj = $irc->plugin_get( 'ExamplePlugin' );

	# We want a list of plugins and objects
	my $hashref = $irc->plugin_list();

	# Oh! We want a list of plugin aliases.
	my @aliases = keys %{ $irc->plugin_list() };

	# Ah, we want to remove the plugin
	$plugin = $irc->plugin_del( 'ExamplePlugin' );

The plugins themselves will conform to the standard API described here. What they can do is
limited only by imagination and the IRC RFC's ;)

	# Import the constants
	use POE::Component::Server::IRC::Plugin qw( :ALL );

	# Our constructor
	sub new {
		...
	}

	# Required entry point for POE::Component::Server::IRC::Backend
	sub PCSI_register {
		my( $self, $irc ) = @_;

		# Register events we are interested in
		$irc->plugin_register( $self, 'SERVER', qw(connection) );

		# Return success
		return 1;
	}

	# Required exit point for PoCo-IRC
	sub PCSI_unregister {
		my( $self, $irc ) = @_;

		# PCSIB will automatically unregister events for the plugin

		# Do some cleanup...

		# Return success
		return 1;
	}

	# Registered events will be sent to methods starting with IRC_
	# If the plugin registered for SERVER - irc_355
	sub IRCD_connection {
		my( $self, $irc, $line ) = @_;

		# Remember, we receive pointers to scalars, so we can modify them
		$$line = 'frobnicate!';

		# Return an exit code
		return PCSI_EAT_NONE;
	}

	# Default handler for events that do not have a corresponding plugin method defined.
	sub _default {
		my( $self, $irc, $event ) = splice @_, 0, 3;

		print "Default called for $event\n";

		# Return an exit code
		return PCSI_EAT_NONE;
	}

=head1 Available methods to use on the $irc object

=head2 plugin_add

	Accepts two arguments:
		The alias for the plugin
		The actual plugin object

	The alias is there for the user to refer to it, as it is possible to have multiple
	plugins of the same kind active in one PoCo-IRC object.

	This method will call $plugin->PCSI_register( $irc )

	Returns 1 if plugin was initialized, undef if not.

=head2 plugin_get

	Accepts one argument:
		The alias for the plugin

	Returns the plugin object if it was found, undef if not.

=head2 plugin_del

	Accepts one argument:
		The alias for the plugin or the plugin object itself

	This method will call $plugin->PCSI_unregister( $irc )

	Returns the plugin object if the plugin was removed, undef if not.

=head2 plugin_list

	Has no arguments.

	Returns a hashref of plugin objects, keyed on alias, or an empty list if there are no
	plugins loaded.

=head2 plugin_register

	Accepts the following arguments:
		The plugin object
		The type of the hook ( 'SERVER' )
		The event name(s) to watch

	The event names can be as many as possible, or an arrayref. They correspond
	to the ircd_backend_* events listed in POE::Component::Server::IRC::Backend, 
	and naturally, arbitrary events too.

	You do not need to supply events with ircd_backend_ in front of them, just the names.

	It is possible to register for all events by specifying 'all' as an event.

	Returns 1 if everything checked out fine, undef if something's seriously wrong

=head2 plugin_unregister

	Accepts the following arguments:
		The plugin object
		The type of the hook ( 'SERVER' )
		The event name(s) to unwatch

	The event names can be as many as possible, or an arrayref. They correspond
	to the ircd_backend_* events listed in POE::Component::Server::IRC::Backend, and naturally, 
	arbitrary events too.

	You do not need to supply events with ircd_backend_ in front of them, just the names.

	Returns 1 if all the event name(s) was unregistered, undef if some was not found

=head1 New SERVER events available to POE::Component::Server::IRC::Backend

=head2 ircd_backend_plugin_add

This event will be triggered after a plugin is added. It receives two arguments, the first being
the plugin name, and the second being the plugin object.

=head2 ircd_backend_plugin_del

This event will be triggered after a plugin is deleted. It receives two arguments, the first being
the plugin name, and the second being the plugin object.

=head1 Event arguments

=head2 SERVER hooks

Hooks that are targeted toward data received from the server will get the exact same
arguments as if it was a normal event, look at the POE::Component::Server::IRC::Backend
docs for more information.

	NOTE: Server methods are identified in the plugin namespace by the subroutine prefix
	of IRCD_*. I.e. an ircd_backend_cmd_kick event handler would be:

	sub IRCD_cmd_kick {}

The only difference is instead of getting scalars, the hook will get a reference to
the scalar, to allow it to mangle the data. This allows the plugin to modify data *before*
they are sent out to registered sessions.

They are required to return one of the exit codes so POE::Component::Server::IRC::Backend will know what to do.

=head3 Names of potential hooks

	socketerr
	connected
	plugin_del

Keep in mind that they are always lowercased, check out the POE::Component::IRC manpage.

=head2 _default

If a plugin doesn't have a specific hook method defined for an event, the component will attempt to call
a plugin's _default() method. The first parameter after the plugin and irc objects will be the handler name.

	sub _default {
	  my ($self,$irc,$event) = splice @_, 0, 3;

	  return PCSI_EAT_NONE;
	}

The _default() handler is expected to return one of the exit codes so POE::Component::Server::IRC::Backend will know what to do.

=head1 Exit Codes

=head2 PCSI_EAT_NONE

	This means the event will continue to be processed by remaining plugins and
	finally, sent to interested sessions that registered for it.

=head2 PCSI_EAT_CLIENT

	This means the event will continue to be processed by remaining plugins but
	it will not be sent to any sessions that registered for it.

=head2 PCSI_EAT_PLUGIN

	This means the event will not be processed by remaining plugins, it will go
	straight to interested sessions.

=head2 PCSI_EAT_ALL

	This means the event will be completely discarded, no plugin or session will see it.

=head1 Plugin ordering system

The plugins are given priority on a first come, first serve basis. Therefore, plugins that were added
before others have the first shot at processing events. Ideas are welcome on a clean system to allow
users to re-order plugins.

=head1 EXPORT

	Exports the return constants for plugins to use in @EXPORT_OK
	Also, the ':ALL' tag can be used to get all of them

=head1 SEE ALSO

L<POE::Component::IRC>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

Ported to POE::Component::Server::IRC by Chris 'BinGOs' Williams E<lt>chris@bingosnet.co.ukE<gt>

=head1 LICENSE

Copyright C<(c)> Chris Williams and Apocalypse

This module may be used, modified, and distributed under the same terms as Perl itself. Please see the license that came with your Perl distribution for details.

=head1 PROPS

The idea is heavily borrowed from X-Chat, BIG thanks goes out to the genius that came up with the EAT_* system :)

=cut
