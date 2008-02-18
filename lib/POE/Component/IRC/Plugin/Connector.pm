package POE::Component::IRC::Plugin::Connector;

use strict;
use warnings;
use POE;
use POE::Component::IRC;
use POE::Component::IRC::Plugin qw( :ALL );

sub new {
    my ($package, %args) = @_;
    $args{ lc $_ } = delete $args{$_} for keys %args;
    $args{lag} = 0;
    return bless \%args, $package;
}

sub PCI_register {
    my ($self, $irc) = splice @_, 0, 2;

    $self->{irc} = $irc;
    $self->{SESSION_ID} = POE::Session->create(
        object_states => [
            $self => [ qw(_start _auto_ping _reconnect _shutdown _start_ping _start_time_out _stop_ping _time_out) ],
        ],
        options => { trace => 0 },
    )->ID();

    $irc->plugin_register( $self, 'SERVER', qw(all) );

    return 1;
}

sub PCI_unregister {
    my ($self, $irc) = splice @_, 0, 2;
    delete $self->{irc};
    $poe_kernel->post( $self->{SESSION_ID} => '_shutdown' );
    $poe_kernel->refcount_decrement( $self->{SESSION_ID}, __PACKAGE__ );
    return 1;
}

sub S_connected {
    my ($self, $irc) = splice @_, 0, 2;
    $poe_kernel->post( $self->{SESSION_ID}, '_start_time_out' );
    return PCI_EAT_NONE;
}

sub S_001 {
    my ($self, $irc) = splice @_, 0, 2;
    $poe_kernel->post( $self->{SESSION_ID}, '_start_ping' );
    return PCI_EAT_NONE;
}

sub S_disconnected {
    my ($self, $irc) = splice @_, 0, 2;
    $poe_kernel->post( $self->{SESSION_ID}, '_stop_ping' );
    $poe_kernel->post( $self->{SESSION_ID}, '_reconnect' );
    return PCI_EAT_NONE;
}

sub S_error {
    my ($self, $irc) = splice @_, 0, 2;
    $poe_kernel->post( $self->{SESSION_ID}, '_stop_ping' );
    $poe_kernel->post( $self->{SESSION_ID}, '_reconnect' );
    return PCI_EAT_NONE;
}

sub S_socketerr {
    my ($self, $irc) = splice @_, 0, 2;
    $poe_kernel->post( $self->{SESSION_ID}, '_stop_ping' );
    $poe_kernel->post( $self->{SESSION_ID}, '_reconnect' );
    return PCI_EAT_NONE;
}

sub S_pong {
    my ($self, $irc) = splice @_, 0, 2;
    my $ping = shift @{ $self->{pings} };
    return PCI_EAT_NONE unless $ping;
    $self->{lag} = time() - $ping;
    $self->{seen_traffic} = 1;
    return PCI_EAT_NONE;
}

sub _default {
    my ($self,$irc) = splice @_, 0, 2;
    $self->{seen_traffic} = 1;
    return PCI_EAT_NONE;
}

sub lag {
    return $_[0]->{lag};
}

sub _start {
    my ($kernel, $self) = @_[KERNEL, OBJECT];

    $self->{SESSION_ID} = $_[SESSION]->ID();
    $kernel->refcount_increment( $self->{SESSION_ID}, __PACKAGE__ );
    $kernel->yield( '_start_ping' ) if $self->{irc}->connected();
    return;
}

sub _start_ping {
    my ($kernel, $self) = @_[KERNEL, OBJECT];
    $self->{pings} = [ ];
    $kernel->delay( '_time_out' => undef );
    $kernel->delay( '_auto_ping' => $self->{delay} || 300 );
    return;
}

sub _auto_ping {
    my ($kernel, $self) = @_[KERNEL, OBJECT];
    
    if (!$self->{seen_traffic}) {
        my $time = time();
        $self->{irc}->yield( 'ping' => $time );
        push @{ $self->{pings} }, $time;
    }

    $self->{seen_traffic} = 0;
    $kernel->yield( '_start_ping' );
    return;
}

sub _stop_ping {
    my ($kernel, $self) = @_[KERNEL, OBJECT];
    delete $self->{pings};
    $kernel->delay( '_auto_ping' => undef );
    $kernel->delay( '_time_out' => undef );
    return;
}

sub _shutdown {
    my ($kernel,$self) = @_[KERNEL, OBJECT];

    $kernel->yield( '_stop_ping' );
    return;
}

sub _reconnect {
    my ($kernel, $self, $session, $sender) = @_[KERNEL, OBJECT, SESSION, SENDER];

    if ($sender eq $session) {
        $self->{irc}->yield( 'connect' );
    }
    else {
        $kernel->delay( '_reconnect' => 60 );
    }
    
    return;
}

sub _start_time_out {
    my ($kernel, $self) = @_[KERNEL, OBJECT];
    $kernel->delay( '_time_out' => $self->{timeout} || 60 );
    return;
}

sub _time_out {
    my ($kernel, $self) = @_[KERNEL, OBJECT];
    $self->{irc}->disconnect();
    return;
}

1;
__END__

=head1 NAME

POE::Component::IRC::Plugin::Connector - A PoCo-IRC plugin that deals with the
messy business of staying connected to an IRC server.

=head1 SYNOPSIS

 use POE qw(Component::IRC Component::IRC::Plugin::Connector);

 my $irc = POE::Component::IRC->spawn();

 POE::Session->create( 
     package_states => [ 
         main => [ qw(_start lag_o_meter) ],
     ],
 );

 $poe_kernel->run();

 sub _start {
     my ($kernel, $heap) = @_[KERNEL ,HEAP];
     $irc->yield( register => 'all' );

     $heap->{connector} = POE::Component::IRC::Plugin::Connector->new();

     $irc->plugin_add( 'Connector' => $heap->{connector} );

     $irc->yield ( connect => { Nick => 'testbot', Server => 'someserver.com' } );

     $kernel->delay( 'lag_o_meter' => 60 );
     return;
 }

 sub lag_o_meter {
     my ($kernel,$heap) = @_[KERNEL,HEAP];
     print 'Time: ' . time() . ' Lag: ' . $heap->{connector}->lag() . "\n";
     $kernel->delay( 'lag_o_meter' => 60 );
     return;
 }

=head1 DESCRIPTION

POE::Component::IRC::Plugin::Connector is a L<POE::Component::IRC|POE::Component::IRC>
plugin that deals with making sure that your IRC bot stays connected to the IRC
network of your choice. It implements the general algorithm as demonstrated at
L<http://poe.perl.org/?POE_Cookbook/IRC_Bot_Reconnecting>.

=head1 METHODS

=over

=item C<new>

Takes one argument, 'delay', which the frequency that the plugin will ping it's
server. Returns a plugin object suitable for use in
L<POE::Component::IRC|POE::Component::IRC>'s 'plugin_add'.

 $irc->plugin_add( 'Connector' => POE::Component::IRC::Plugin::Connector->new( delay => 120 ) );

=item C<lag>

Returns the current 'lag' in seconds between sending PINGs to the IRC server
and getting PONG responses. Probably not likely to be wholely accurate.

=back

=head1 AUTHOR

Chris "BinGOs" Williams <chris@bingosnet.co.uk>

=head1 SEE ALSO

L<POE::Component::IRC|POE::Component::IRC>

L<POE::Component::IRC::Plugin|POE::Component::IRC::Plugin>

=cut
