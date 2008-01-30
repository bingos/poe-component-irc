# Declare our package
package POE::Component::IRC::Plugin;

# We export some stuff
require Exporter;
@ISA = qw( Exporter );
%EXPORT_TAGS = ( 'ALL' => [ qw( PCI_EAT_NONE PCI_EAT_CLIENT PCI_EAT_PLUGIN PCI_EAT_ALL ) ] );
Exporter::export_ok_tags( 'ALL' );

# Standard stuff to catch errors
use strict;				# Make sure we can't mess up
use warnings;				# Enable warnings to catch errors
use vars qw($VERSION);

# Initialize our version
$VERSION = '0.09';


# Our constants
sub PCI_EAT_NONE	() { 1 }
sub PCI_EAT_CLIENT	() { 2 }
sub PCI_EAT_PLUGIN	() { 3 }
sub PCI_EAT_ALL		() { 4 }

1;
__END__
=head1 NAME

POE::Component::IRC::Plugin - Provides plugin documentation for PoCo-IRC

=head1 ABSTRACT

	Provides plugin documentation for PoCo-IRC

=head1 CHANGES

=head2 0.08

	Added EXAMPLES section.

=head2 0.07

	The plugin sytem has changed to use L<POE::Component::IRC::Pipeline> now.  See its documentation
	for information about the underlying operations of the pipeline.

	There's a new method, plugin_order, which returns an array reference of the plugins in the pipeline
	in the order in which they are executed.

	There's a new method, pipeline, which returns the POE::Component::IRC::Pipeline object so you can
	deal with its finer-tuned controls yourself.

	The _plugin_unregister_do method is no more.

=head2 0.06

	Updated _plugin_process so that it runs plugin method calls in an 'eval'. Rogue plugins shouldn't be
	able to crash the component now.

	If a plugin doesn't have a event handler method defined now, the component will try to call a 
	_default() handler instead.

=head2 0.05

	Realized that there would be collision between USER/SERVER methods, so made it distinct by using S_* and U_*
	Clarified the documentation to stress that 'irc_' is not required for event names
	Changed the description of the 2 new events to stress that they are sent *after* the action is done

=head2 0.04

	Changed _plugin_register/unregister to non-private methods

=head2 0.03

	As per perigrin's suggestion, added 2 new event types to monitor plugin add/del
	Updated the name from PoCo-IRC-Plugins to PoCo-IRC-Plugin
	Updated return value ( PCI_EAT_PLUGINS to PCI_EAT_PLUGIN )
	Updated plugin_del to also accept the plugin object instead of a name

=head2 0.02

	Modified plugin_del() so it returns the plugin object

=head2 0.01

	Initial release

=head1 Why do we need this?

Certain individuals in #PoE on MAGNet said we didn't need to bloat the PoCo-IRC code...

BinGOs, the current maintainer of the module, and I heartily agreed that this is a wise choice.

One example:

	Look at the magnificent new feature in 3.4 -> irc_whois replies! Yes, that is a feature I bet
	most of us have been coveting for a while, as it definitely makes our life easier. It was
	implemented in 30 minutes or so after a request, the maintainer said. I replied by saying that
	it's a wonderful idea, but what would happen if somebody else asked for a new feature? Maybe that
	feature is something we all would love to have, so should it be put in the core? Plugins allow the
	core to stay lean and mean, while delegating additional functionality to outside modules. BinGOs' work
	with making PoCo-IRC inheritable is wonderful, but what if there were 2 modules which have features
	that you would love to have in your bot? Inherit from both? Imagine the mess...

	Here comes plugins to the rescue :)

You could say Bot::Pluggable does the job, and so on, but if this feature were put into the core, it would
allow PoCo-IRC to be extended beyond our wildest dreams, and allow the code to be shared amongst us all, giving
us superior bug smashing abilities.

Yes, there are changes that most of us will moan when we go update our bots to use the new $irc object system,
but what if we also used this opportunity to improve PoCo-IRC even more and give it a lifespan until Perl8 or
whatever comes along? :)

=head1 DESCRIPTION

This is the document coders/users should refer to when using/developing plugins for
POE::Component::IRC.

The plugin system works by letting coders hook into the two aspects of PoCo-IRC:

	Data received from the server
	User commands about to be sent to the server

The goal of this system is to make PoCo-IRC so easy to extend, enabling it to Take Over
The World! *Just Kidding*

The general architecture of using the plugins should be:

	# Import the stuff...
	use POE;
	use POE::Component::IRC;
	use POE::Component::IRC::Plugin::ExamplePlugin;

	# Create our session here
	POE::Session->create( ... );

	# Create the IRC session here
	my $irc = POE::Component::IRC->spawn() or die 'Nooo!';

	# Create the plugin
	# Of course it could be something like $plugin = MyPlugin->new();
	my $plugin = POE::Component::IRC::Plugin::ExamplePlugin->new( ... );

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
	use POE::Component::IRC::Plugin qw( :ALL );

	# Our constructor
	sub new {
		...
	}

	# Required entry point for PoCo-IRC
	sub PCI_register {
		my( $self, $irc ) = @_;

		# Register events we are interested in
		$irc->plugin_register( $self, 'SERVER', qw( 355 kick whatever) );

		# Return success
		return 1;
	}

	# Required exit point for PoCo-IRC
	sub PCI_unregister {
		my( $self, $irc ) = @_;

		# PCI will automatically unregister events for the plugin

		# Do some cleanup...

		# Return success
		return 1;
	}

	# Registered events will be sent to methods starting with IRC_
	# If the plugin registered for SERVER - irc_355
	sub S_355 {
		my( $self, $irc, $line ) = @_;

		# Remember, we receive pointers to scalars, so we can modify them
		$$line = 'frobnicate!';

		# Return an exit code
		return PCI_EAT_NONE;
	}

	# Default handler for events that do not have a corresponding plugin method defined.
	sub _default {
		my( $self, $irc, $event ) = splice @_, 0, 3;

		print "Default called for $event\n";

		# Return an exit code
		return PCI_EAT_NONE;
	}

=head1 Available methods to use on the $irc object

=head2 pipeline

	This method returns (or creates) the pipeline object into which plugins are stored.

=head2 plugin_add

	Accepts two arguments:
		The alias for the plugin
		The actual plugin object

	The alias is there for the user to refer to it, as it is possible to have multiple
	plugins of the same kind active in one PoCo-IRC object.

	This method goes through the pipeline's push() method.

	This method will call $plugin->PCI_register( $irc )

	Returns the number of plugins now in the pipeline if plugin was initialized, undef
	if not.

=head2 plugin_get

	Accepts one argument:
		The alias for the plugin

	This method goes through the pipeline's get() method.

	Returns the plugin object if it was found, undef if not.

=head2 plugin_del

	Accepts one argument:
		The alias for the plugin or the plugin object itself

	This method goes through the pipeline's remove() method.

	This method will call $plugin->PCI_unregister( $irc )

	Returns the plugin object if the plugin was removed, undef if not.

=head2 plugin_list

	Has no arguments.

	Returns a hashref of plugin objects, keyed on alias, or an empty list if there are no
	plugins loaded.

=head2 plugin_order

	Has no arguments.

	Returns an arrayref of plugin objects, in the order which they are encountered in the
        pipeline.

=head2 plugin_register

	Accepts the following arguments:
		The plugin object
		The type of the hook ( 'SERVER' or 'USER' )
		The event name(s) to watch

	The event names can be as many as possible, or an arrayref. They correspond
	to the irc_* events listed in PoCo-IRC, and naturally, arbitrary events too.

	You do not need to supply events with irc_ in front of them, just the names.

	It is possible to register for all events by specifying 'all' as an event.

	Returns 1 if everything checked out fine, undef if something's seriously wrong

=head2 plugin_unregister

	Accepts the following arguments:
		The plugin object
		The type of the hook ( 'SERVER' or 'USER' )
		The event name(s) to unwatch

	The event names can be as many as possible, or an arrayref. They correspond
	to the irc_* events listed in PoCo-IRC, and naturally, arbitrary events too.

	You do not need to supply events with irc_ in front of them, just the names.

	Returns 1 if all the event name(s) was unregistered, undef if some was not found

=head1 New SERVER events available to PoCo-IRC

=head2 irc_plugin_add

This event will be triggered after a plugin is added. It receives two arguments, the first being
the plugin name, and the second being the plugin object.

=head2 irc_plugin_del

This event will be triggered after a plugin is deleted. It receives two arguments, the first being
the plugin name, and the second being the plugin object.

=head1 Event arguments

=head2 SERVER hooks

Hooks that are targeted toward data received from the server will get the exact same
arguments as if it was a normal event, look at the PoCo-IRC docs for more information.

	NOTE: Server methods are identified in the plugin namespace by the subroutine prefix
	of S_*. I.e. an irc_kick event handler would be:

	sub S_kick {}

The only difference is instead of getting scalars, the hook will get a reference to
the scalar, to allow it to mangle the data. This allows the plugin to modify data *before*
they are sent out to registered sessions.

They are required to return one of the exit codes so PoCo-IRC will know what to do.

=head3 Names of potential hooks

	001
	socketerr
	connected
	plugin_del

Keep in mind that they are always lowercased, check out the POE::Component::IRC manpage and look at
the Important Events section for the complete list of names.

=head2 USER hooks

These type of hooks have two different argument formats. They are split between data sent to
the server, and data sent through DCC connections.

	NOTE: User methods are identified in the plugin namespace by the subroutine prefix
	of U_*. I.e. an irc_kick event handler would be:

	sub U_kick {}

Hooks that are targeted to user data have it a little harder. They will receive a reference
to the raw line about to be sent out. That means they will have to parse it in order to
extract data out of it.

The reasoning behind this is that it is not possible to insert hooks in every method in the
$irc object, as it will become unwieldy and not allow inheritance to work.

The DCC hooks have it easier, as they do not interact with the server, and will receive references
to the arguments specified in the PoCo-IRC pod regarding dcc commands.

=head3 Names of potential hooks

	kick
	dcc_chat
	ison
	privmsg

Keep in mind that they are always lowercased, and are extracted from the raw line about to be sent to the
irc server. To be able to parse the raw line, some RFC reading is in order. These are the DCC events that
are not given a raw line, they are:

	dcc		-	$nick, $type, $file, $blocksize
	dcc_accept	-	$cookie, $myfile
	dcc_resume	-	$cookie
	dcc_chat	-	$cookie, @lines
	dcc_close	-	$cookie

=head2 _default

If a plugin doesn't have a specific hook method defined for an event, the component will attempt to call
a plugin's _default() method. The first parameter after the plugin and irc objects will be the handler name.

	sub _default {
	  my ($self,$irc,$event) = splice @_, 0, 3;

	  # $event will be something like S_public or U_dcc, etc.
	  return PCI_EAT_NONE;
	}

The _default() handler is expected to return one of the exit codes so PoCo-IRC will know what to do.

=head1 Exit Codes

=head2 PCI_EAT_NONE

	This means the event will continue to be processed by remaining plugins and
	finally, sent to interested sessions that registered for it.

=head2 PCI_EAT_CLIENT

	This means the event will continue to be processed by remaining plugins but
	it will not be sent to any sessions that registered for it. This means nothing
	will be sent out on the wire if it was an USER event, beware!

=head2 PCI_EAT_PLUGIN

	This means the event will not be processed by remaining plugins, it will go
	straight to interested sessions.

=head2 PCI_EAT_ALL

	This means the event will be completely discarded, no plugin or session will see it. This
	means nothing will be sent out on the wire if it was an USER event, beware!

=head1 Plugin ordering system

See L<POE::Component::IRC::Pipeline|POE::Component::IRC::Pipeline>

=head1 EXPORT

	Exports the return constants for plugins to use in @EXPORT_OK
	Also, the ':ALL' tag can be used to get all of them

=head1 EXAMPLES

=over

=item A simple ROT13 'encryption' plugin

  package Rot13;

  use strict qw(subs vars refs);    # Make sure we can't mess up
  use warnings FATAL => 'all';
  use POE::Component::IRC::Plugin qw( :ALL );

  # Plugin object constructor
  sub new {
    my $package = shift;
    return bless {}, $package;
  }

  sub PCI_register {
    my ( $self, $irc ) = splice @_, 0, 2;

    $irc->plugin_register( $self, 'SERVER', qw(public) );
    return 1;
  }

  # This is method is mandatory but we don't actually have anything to do.
  sub PCI_unregister {
    return 1;
  }

  sub S_public {
    my ( $self, $irc ) = splice @_, 0, 2;

    # Parameters are passed as scalar-refs including arrayrefs.
    my $nick    = ( split /!/, ${ $_[0] } )[0];
    my $channel = ${ $_[1] }->[0];
    my $msg     = ${ $_[2] };

    if ( my ($rot13) = $msg =~ /^rot13 (.+)/ ) {
        $rot13 =~ tr[a-zA-Z][n-za-mN-ZA-M];

        # Send a response back to the server.
        $irc->yield( privmsg => $channel => $rot13 );
        return PCI_EAT_PLUGIN;    # We don't want other plugins to process this
    }

    return PCI_EAT_NONE; # Default action is to allow other plugins to process it.
  }

=item A template for a plugin with it's own L<POE::Session>

  package POE-Plugin-Template;

  use POE;
  use POE::Component::IRC::Plugin qw( :ALL );

  sub new {
    my $package = shift;
    my $self = bless {@_}, $package;
    return $self;
  }

  sub PCI_register {
    my ( $self, $irc ) = splice @_, 0, 2;

    # We store a ref to the $irc object so we can use it in our
    # session handlers.
    $self->{irc} = $irc;

    $irc->plugin_register( $self, 'SERVER', qw(blah blah blah) );

    $self->{SESSION_ID} = POE::Session->create(
        object_states => [
            $self => [qw(_start _shutdown)],
        ],
    )->ID();

    return 1;
  }

  sub PCI_unregister {
    my ( $self, $irc ) = splice @_, 0, 2;
    # Plugin is dying make sure our POE session does as well.
    $poe_kernel->call( $self->{SESSION_ID} => '_shutdown' );
    delete $self->{irc};
    return 1;
  }

  sub _start {
    my ( $kernel, $self ) = @_[ KERNEL, OBJECT ];
    $self->{SESSION_ID} = $_[SESSION]->ID();
    # Make sure our POE session stays around. Could use aliases but that is so messy :)
    $kernel->refcount_increment( $self->{SESSION_ID}, __PACKAGE__ );
    undef;
  }

  sub _shutdown {
    my ($kernel, $self) = @_[ KERNEL, OBJECT ];
    $kernel->alarm_remove_all();
    $kernel->refcount_decrement( $self->{SESSION_ID}, __PACKAGE__ );
    undef;
  }

=back

=head1 SEE ALSO

L<POE::Component::IRC> 

L<POE::Component::IRC::Pipeline>

L<POE::Session>

=head1 AUTHOR

Apocalypse E<lt>apocal@cpan.orgE<gt>

=head1 PROPS

The idea is heavily borrowed from X-Chat, BIG thanks goes out to the genius that came up with the EAT_* system :)

=cut
