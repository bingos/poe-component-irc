package POE::Component::Server::IRC::Backend;

use strict;
use warnings;
use POE qw(Wheel::SocketFactory Wheel::ReadWrite Filter::Stackable Filter::Line Filter::IRCD);
use POE::Component::Server::IRC::Plugin qw( :ALL );
use POE::Component::Server::IRC::Pipeline;
use Socket;
use Carp;
use Net::Netmask;
use vars qw($VERSION);

$VERSION = '1.22';

sub create {
  my $package = shift;
  croak "$package requires an even number of parameters" if @_ & 1;
  my %parms = @_;

  $parms{ lc $_ } = delete $parms{$_} for keys %parms;

  my $self = bless \%parms, $package;

  $self->{prefix} = 'ircd_backend_' unless $self->{prefix};
  $self->{antiflood} = 1 unless defined $self->{antiflood} and $self->{antiflood} eq '0';
  my $options = delete $self->{options};
  my $sslify_options = delete $self->{sslify_options};

  $self->{session_id} = POE::Session->create(
	object_states => [
		$self => { _start	 => '_start',
			   add_connector => '_add_connector',
			   add_filter    => '_add_filter',
			   add_listener  => '_add_listener', 
			   del_filter    => '_del_filter',
			   del_listener  => '_del_listener', 
			   send_output   => '_send_output',
			   shutdown 	 => '_shutdown', },
		$self => [ qw(  __send_event
				__send_output
				_accept_connection 
				_accept_failed 
				_auth_client
				_auth_done
				_conn_alarm
				_conn_input 
				_conn_error 
				_conn_flushed
				_event_dispatcher
				_got_hostname_response
				_got_ip_response
				_sock_failed
				_sock_up
				_start 
				ident_agent_error
				ident_agent_reply
				register 
				unregister) ],
	],
	heap => $self,
	( ref($options) eq 'HASH' ? ( options => $options ) : () ),
  )->ID();
  $self->{got_zlib} = 0;
  eval { 
	require POE::Filter::Zlib::Stream; 
	$self->{got_zlib} = 1;
  };

  if ( $sslify_options and ref $sslify_options eq 'ARRAY' ) {
    $self->{got_ssl} = $self->{got_server_ssl} = 0;
    eval {
	require POE::Component::SSLify; 
	import POE::Component::SSLify qw(SSLify_Options Server_SSLify Client_SSLify);
	$self->{got_ssl} = 1;
    };
    warn "$@\n" if $@;
    if ( $self->{got_ssl} ) {
	eval { SSLify_Options( @{ $sslify_options } ); };
        $self->{got_server_ssl} = 1 unless $@;
	warn "$@\n" if $@;
    }
  }

  return $self;
}

sub session_id {
  my $self = shift;
  return $self->{session_id};
}

sub yield {
  my $self = shift;
  $poe_kernel->post( $self->session_id() => @_ );
}

sub call {
  my $self = shift;
  $poe_kernel->call( $self->session_id() => @_ );
}

sub _start {
  my ($kernel,$self,$sender) = @_[KERNEL,OBJECT,SENDER];

  $self->{session_id} = $_[SESSION]->ID();

  if ( $self->{alias} ) {
	$kernel->alias_set( $self->{alias} );
  } else {
	$kernel->refcount_increment( $self->{session_id} => __PACKAGE__ );
  }

  $self->{ircd_filter} = POE::Filter::IRCD->new( DEBUG => $self->{debug}, colonify => 1 );
  $self->{line_filter} = POE::Filter::Line->new( InputRegexp => '\015?\012', OutputLiteral => "\015\012" );
  $self->{filter} = POE::Filter::Stackable->new( Filters => [ $self->{line_filter}, $self->{ircd_filter} ] );
  $self->{can_do_auth} = 0;
  eval {
	require POE::Component::Client::Ident::Agent;
	require POE::Component::Client::DNS;
  };
  unless ( $@ ) {
	$self->{resolver} = POE::Component::Client::DNS->spawn( Alias => 'poco_dns_' . $self->{session_id}, Timeout => 10 );
	$self->{can_do_auth} = 1;
  }
  $self->{will_do_auth} = 0;
  if ( $self->{auth} and $self->{can_do_auth} ) {
	$self->{will_do_auth} = 1;
  }
  $self->_load_our_plugins();
  if ( $kernel != $sender ) {
    $self->{sessions}->{ $sender->ID }++;
    $kernel->post( $sender => $self->{prefix} . 'registered' => $self );
  }
  undef;
}

sub _load_our_plugins {
  return 1;
}

###################
# Control methods #
###################

sub register {
  my ($kernel,$self,$session,$sender) = @_[KERNEL,OBJECT,SESSION,SENDER];
  $session = $session->ID(); $sender = $sender->ID();

  $self->{sessions}->{ $sender }++;
  $kernel->refcount_increment( $sender => __PACKAGE__ ) if $self->{sessions}->{ $sender } == 1 and $sender ne $session;
  $kernel->post( $sender => $self->{prefix} . 'registered' => $self );
  undef;
}

sub unregister {
  my ($kernel,$self,$session,$sender) = @_[KERNEL,OBJECT,SESSION,SENDER];
  $session = $session->ID(); $sender = $sender->ID();

  delete $self->{sessions}->{ $sender };
  $kernel->refcount_decrement( $sender => __PACKAGE__ ) if $sender ne $session;
  $kernel->post( $sender => $self->{prefix} . 'unregistered' );
  undef;
}

sub shutdown {
  my ($self) = shift;
  $self->yield( 'shutdown' => @_ );
}

sub _shutdown {
  my ($kernel,$self) = @_[KERNEL,OBJECT];

  $kernel->alias_remove( $_ ) for $kernel->alias_list();
  $kernel->refcount_decrement( $self->{session_id} => __PACKAGE__ ) unless $self->{alias};

  $self->{terminating} = 1;
  delete $self->{listeners};
  delete $self->{connectors};
  delete $self->{wheels}; # :)
  $kernel->alarm_remove_all();
  $kernel->refcount_decrement( $_ => __PACKAGE__ ) for keys %{ $self->{sessions} };
  $self->_unload_our_plugins();
  undef;
}

sub _unload_our_plugins {
  return 1;
}

sub send_event {
  my $self = shift;
  my $event = shift;

  return 0 unless $event;
  my $prefix = $self->{prefix};
  $event = $prefix . $event unless $event =~ /^(_|\Q$prefix\E)/;
  $self->yield( '__send_event' => $event => @_ );
  return 1;
}

sub __send_event {
  my( $self, $event, @args ) = @_[ OBJECT, ARG0, ARG1 .. $#_ ];
  $self->_send_event( $event, @args );
  return 1;
}

sub _send_event {
  my ($self,$event,@args) = @_;
  return 1 if $self->_plugin_process( 'SERVER', $event, \( @args ) ) == PCSI_EAT_ALL;
  $poe_kernel->post( $_ => $event, @args ) for  keys % { $self->{sessions} };
  return 1;
}

############################
# Listener related methods #
############################

sub _accept_failed {
  my ($kernel,$self,$operation,$errnum,$errstr,$listener_id) = @_[KERNEL,OBJECT,ARG0..ARG3];
  delete $self->{listeners}->{ $listener_id };
  $self->_send_event( $self->{prefix} . 'listener_failure', $listener_id, $operation, $errnum, $errstr );
  undef;
}

sub _accept_connection {
  my ($kernel,$self,$socket,$peeraddr,$peerport,$listener_id) = @_[KERNEL,OBJECT,ARG0..ARG3];
  my $sockaddr = inet_ntoa( ( unpack_sockaddr_in ( getsockname $socket ) )[1] );
  my $sockport = ( unpack_sockaddr_in ( getsockname $socket ) )[0];
  $peeraddr = inet_ntoa( $peeraddr );
  my $listener = $self->{listeners}->{ $listener_id };

  if ( $self->{got_server_ssl} and $listener->{usessl} ) {
	eval { $socket = POE::Component::SSLify::Server_SSLify( $socket ); };
	warn "$@\n" if $@;
  }

  return if $self->denied( $peeraddr );

  my $wheel = POE::Wheel::ReadWrite->new(
	Handle => $socket,
	Filter => $self->{filter},
	InputEvent => '_conn_input',
	ErrorEvent => '_conn_error',
	FlushedEvent => '_conn_flushed',
  );

  if ( $wheel ) {
	my $wheel_id = $wheel->ID();
        my $ref = { wheel => $wheel, peeraddr => $peeraddr, peerport => $peerport, flooded => 0,
		      sockaddr => $sockaddr, sockport => $sockport, idle => time(), antiflood => $listener->{antiflood}, compress => 0 };
	$self->_send_event( $self->{prefix} . 'connection' => $wheel_id => $peeraddr => $peerport => $sockaddr => $sockport );
	if ( $listener->{do_auth} and $self->{will_do_auth} ) {
		$kernel->yield( '_auth_client' => $wheel_id );
	} else {
		$self->_send_event( $self->{prefix} . 'auth_done' => $wheel_id => { ident    => '',
										    hostname => '' } )
	}
	$ref->{freq} = $listener->{freq};
        $ref->{alarm} = $kernel->delay_set( _conn_alarm => $listener->{freq} => $wheel_id );
	$self->{wheels}->{ $wheel_id } = $ref;
  }
  undef;
}

sub add_listener {
  my ($self) = shift;
  croak "add_listener requires an even number of parameters" if @_ & 1;
  $self->yield( 'add_listener' => @_ );
}

sub _add_listener {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  my %parms = @_[ARG0..$#_];

  $parms{ lc($_) } = delete $parms{$_} for keys %parms;

  my $bindport = $parms{port} || 0;
  my $freq = $parms{freq} || 180;
  my $auth = 1;
  my $antiflood = 1;
  my $usessl = 0;
  $usessl = 1 if $parms{usessl};
  $auth = 0 if defined $parms{auth} and $parms{auth} eq '0';
  $antiflood = 0 if defined $parms{antiflood} and $parms{antiflood} eq '0';

  my $listener = POE::Wheel::SocketFactory->new(
	BindPort => $bindport,
	( $parms{bindaddr} ? ( BindAddress => $parms{bindaddr} ) : () ),
	Reuse => 'on',
	( $parms{listenqueue} ? ( ListenQueue => $parms{listenqueue} ) : () ),
	SuccessEvent => '_accept_connection',
	FailureEvent => '_accept_failed',
  );

  if ( $listener ) {
	my $port = ( unpack_sockaddr_in( $listener->getsockname ) )[0];
	my $listener_id = $listener->ID();
	$self->_send_event( $self->{prefix} . 'listener_add' => $port => $listener_id );
	$self->{listening_ports}->{ $port } = $listener_id;
	$self->{listeners}->{ $listener_id }->{wheel} = $listener;
	$self->{listeners}->{ $listener_id }->{port} = $port;
	$self->{listeners}->{ $listener_id }->{freq} = $freq;
	$self->{listeners}->{ $listener_id }->{do_auth} = $auth;
	$self->{listeners}->{ $listener_id }->{antiflood} = $antiflood;
	$self->{listeners}->{ $listener_id }->{usessl} = $usessl;
  }
  undef;
}

sub del_listener {
  my ($self) = shift;
  croak "add_listener requires an even number of parameters" if @_ & 1;
  $self->yield( 'del_listener' => @_ );
}

sub _del_listener {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  my %parms = @_[ARG0..$#_];

  $parms{ lc($_) } = delete $parms{$_} for keys %parms;

  my $listener_id = delete $parms{listener};
  my $port = delete $parms{port};

  if ( $self->_listener_exists( $listener_id ) ) {
	$port = delete $self->{listeners}->{ $listener_id }->{port};
	delete $self->{listening_ports}->{ $port };
	delete $self->{listeners}->{ $listener_id };
	$self->_send_event( $self->{prefix} . 'listener_del' => $port => $listener_id );
  }

  if ( $self->_port_exists( $port ) ) {
	$listener_id = delete $self->{listening_ports}->{ $port };
	delete $self->{listeners}->{ $listener_id };
	$self->_send_event( $self->{prefix} . 'listener_del' => $port => $listener_id );
  }

  undef;
}

sub _listener_exists {
  my $self = shift;
  my $listener_id = shift || return 0;
  return 1 if defined $self->{listeners}->{ $listener_id };
  return 0;
}

sub _port_exists {
  my $self = shift;
  my $port = shift || return 0;
  return 1 if defined $self->{listening_ports}->{ $port };
  return 0;
}

#############################
# Connector related methods #
#############################

sub add_connector {
  my $self = shift;
  croak "add_connector requires an even number of parameters" if @_ & 1;
  $self->yield( 'add_connector' => @_ );
}

sub _add_connector {
  my ($kernel,$self,$sender) = @_[KERNEL,OBJECT,SENDER];
  #croak "add_connector requires an even number of parameters" if @_[ARG0..$#_] & 1;
  my %parms = @_[ARG0..$#_];

  $parms{ lc($_) } = delete $parms{$_} for keys %parms;
  
  my $remoteaddress = $parms{remoteaddress};
  my $remoteport = $parms{remoteport};
  
  return unless $remoteaddress and $remoteport;

  my $wheel = POE::Wheel::SocketFactory->new(
	SocketDomain   => AF_INET,
	SocketType     => SOCK_STREAM,
	SocketProtocol => 'tcp',
	RemoteAddress => $remoteaddress,
	RemotePort    => $remoteport,
	SuccessEvent  => '_sock_up',
	FailureEvent  => '_sock_failed',
	( $parms{bindaddress} ? ( BindAddress => $parms{bindaddress} ) : () ),
  );

  if ( $wheel ) {
	$parms{wheel} = $wheel;
	$self->{connectors}->{ $wheel->ID() } = \%parms;
  }
  undef;
}

sub _sock_failed {
  my ($kernel,$self,$op,$errno,$errstr,$connector_id) = @_[KERNEL,OBJECT,ARG0..ARG3];
  my $ref = delete $self->{connectors}->{ $connector_id };
  delete $ref->{wheel};
  $self->_send_event( $self->{prefix} . 'socketerr' => $ref );
  undef;
}

sub _sock_up {
  my ($kernel,$self,$socket,$peeraddr,$peerport,$connector_id) = @_[KERNEL,OBJECT,ARG0..ARG3];
  $peeraddr = inet_ntoa( $peeraddr );

  my $cntr = delete $self->{connectors}->{ $connector_id };
  if ( $self->{got_ssl} and $cntr->{usessl} ) {
    eval {
      $socket = POE::Component::SSLify::Client_SSLify( $socket );
    };
    warn "Couldn't use an SSL socket: $@ \n" if $@;
  }

  my $wheel = POE::Wheel::ReadWrite->new(
	Handle => $socket,
	#Filter => $self->{filter},
	Filter => POE::Filter::Stackable->new( Filters => [ $self->{filter} ] ),
	InputEvent => '_conn_input',
	ErrorEvent => '_conn_error',
	FlushedEvent => '_conn_flushed',
  );

  if ( $wheel ) {
	my $wheel_id = $wheel->ID();
	my $sockaddr = inet_ntoa( ( unpack_sockaddr_in ( getsockname $socket ) )[1] );
	my $sockport = ( unpack_sockaddr_in ( getsockname $socket ) )[0];
        my $ref = { wheel => $wheel, peeraddr => $peeraddr, peerport => $peerport, 
		      sockaddr => $sockaddr, sockport => $sockport, idle => time(), antiflood => 0, compress => 0 };
	$self->{wheels}->{ $wheel_id } = $ref;
	$self->_send_event( $self->{prefix} . 'connected' => $wheel_id => $peeraddr => $peerport => $sockaddr => $sockport => $cntr->{name} );
  }
  undef;
}

##############################
# Generic Connection Handler #
##############################

#sub add_filter {
#  my $self = shift;
#  croak "add_filter requires an even number of parameters" if @_ & 1;
#  $self->call( 'add_filter' => @_ );
#}

sub _add_filter {
  my ($kernel,$self,$sender) = @_[KERNEL,OBJECT,SENDER];
  my $wheel_id = $_[ARG0] || croak "You must supply a connection id\n";
  my $filter = $_[ARG1] || croak "You must supply a filter object\n";
  return unless $self->_wheel_exists( $wheel_id );
  my $stackable = POE::Filter::Stackable->new( Filters => [ $self->{line_filter}, $self->{ircd_filter}, $filter ] );
  if ( $self->compressed_link( $wheel_id ) ) {
	$stackable->unshift( POE::Filter::Zlib::Stream->new() );
  }
  $self->{wheels}->{ $wheel_id }->{wheel}->set_filter( $stackable );
  $self->_send_event( $self->{prefix} . 'filter_add' => $wheel_id => $filter );
  undef;
}

sub _anti_flood {
  my ($self,$wheel_id,$input) = splice @_, 0, 3;
  my $current_time = time();

  return unless $wheel_id and $self->_wheel_exists( $wheel_id ) and $input; 
  SWITCH: { 
     if ( $self->{wheels}->{ $wheel_id }->{flooded} ) {
	last SWITCH;
     }
     if ( ( not $self->{wheels}->{ $wheel_id }->{timer} ) or $self->{wheels}->{ $wheel_id }->{timer} < $current_time ) {
	$self->{wheels}->{ $wheel_id }->{timer} = $current_time;
    	my $event = $self->{prefix} . 'cmd_' . lc ( $input->{command} );
    	$self->_send_event( $event => $wheel_id => $input );
	last SWITCH;
     }
     if ( $self->{wheels}->{ $wheel_id }->{timer} <= ( $current_time + 10 ) ) {
	$self->{wheels}->{ $wheel_id }->{timer} += 1;
	push @{ $self->{wheels}->{ $wheel_id }->{msq} }, $input;
	push @{ $self->{wheels}->{ $wheel_id }->{alarm_ids} }, $poe_kernel->alarm_set( '_event_dispatcher' => $self->{wheels}->{ $wheel_id }->{timer} => $wheel_id );
	last SWITCH;
     }
     $self->{wheels}->{ $wheel_id }->{flooded} = 1;
     $self->_send_event( $self->{prefix} . 'connection_flood' => $wheel_id );
  }
  return 1;
}

sub _conn_error {
  my ($self,$errstr,$wheel_id) = @_[OBJECT,ARG2,ARG3];
  return unless $self->_wheel_exists( $wheel_id );
  $self->_disconnected( $wheel_id, $errstr || $self->{wheels}->{ $wheel_id }->{disconnecting} );
  undef;
}

sub _conn_alarm {
  my ($kernel,$self,$wheel_id) = @_[KERNEL,OBJECT,ARG0];
  return unless $self->_wheel_exists( $wheel_id );
  my $conn = $self->{wheels}->{ $wheel_id };
  $self->_send_event( $self->{prefix} . 'connection_idle' => $wheel_id => $conn->{freq} );
  $conn->{alarm} = $kernel->delay_set( _conn_alarm => $conn->{freq} => $wheel_id );
  undef;
}

sub _conn_flushed {
  my ($kernel,$self,$wheel_id) = @_[KERNEL,OBJECT,ARG0];
  return unless $self->_wheel_exists( $wheel_id );
  if ( $self->{wheels}->{ $wheel_id }->{disconnecting} ) {
	$self->_disconnected( $wheel_id, $self->{wheels}->{ $wheel_id }->{disconnecting} );
	return;
  }
  if ( $self->{wheels}->{ $wheel_id }->{compress_pending} ) {
	delete $self->{wheels}->{ $wheel_id }->{compress_pending};
	$self->{wheels}->{ $wheel_id }->{wheel}->get_input_filter()->unshift( POE::Filter::Zlib::Stream->new() );
	$self->_send_event( $self->{prefix} . 'compressed_conn' => $wheel_id );
	return;
  }
  undef;
}

sub _conn_input {
  my ($kernel,$self,$input,$wheel_id) = @_[KERNEL,OBJECT,ARG0,ARG1];
  my $conn = $self->{wheels}->{ $wheel_id };

  $self->_send_event( $self->{prefix} . 'raw_input' => $wheel_id => $input->{raw_line} ) if $self->{raw_events};
  $conn->{seen} = time();
  $kernel->delay_adjust( $conn->{alarm} => $conn->{freq} );
  #ToDo: Antiflood code
  if ( $self->antiflood( $wheel_id ) ) {
	$self->_anti_flood( $wheel_id => $input );
  } else {
    my $event = $self->{prefix} . 'cmd_' . lc $input->{command};
    $self->_send_event( $event => $wheel_id => $input );
  }
  undef;
}

#sub del_filter {
#  my $self = shift;
#  $self->call( 'del_filter' => @_ );
#}

sub _del_filter {
  my ($kernel,$self,$sender) = @_[KERNEL,OBJECT,SENDER];
  my $wheel_id = $_[ARG0] || croak "You must supply a connection id\n";
  return unless $self->_wheel_exists( $wheel_id );
  $self->{wheels}->{ $wheel_id }->{wheel}->set_filter( $self->{filter} );
  $self->_send_event( $self->{prefix} . 'filter_del' => $wheel_id );
  undef;
}

sub _event_dispatcher {
  my ($kernel,$self,$wheel_id) = @_[KERNEL,OBJECT,ARG0];

  return unless $self->_wheel_exists( $wheel_id ) and !$self->{wheels}->{ $wheel_id }->{flooded};
  shift @{ $self->{wheels}->{ $wheel_id }->{alarm_ids} };
  my $input = shift @{ $self->{wheels}->{ $wheel_id }->{msq} };
  if ( $input ) {
    my $event = $self->{prefix} . 'cmd_' . lc ( $input->{command} );
    $self->_send_event( $event => $wheel_id => $input );
  }
  undef;
}

sub send_output {
  my ($self,$output) = splice @_, 0, 2;
  if ( $output and ref( $output ) eq 'HASH' ) {
    if ( scalar @_ == 1 or ( $output->{command} and $output->{command} eq 'ERROR' ) ) {
  	$self->{wheels}->{ $_ }->{wheel}->put( $output ) for grep { $self->_wheel_exists( $_ ) } @_;
    	return 1;
    }
    $self->yield( __send_output => $output => $_ ) for grep { $self->_wheel_exists($_) } @_;
    return 1;
  }
  return 0;
}

sub __send_output {
  my ($self,$output,$route_id) = @_[OBJECT,ARG0,ARG1];
  $self->{wheels}->{ $route_id }->{wheel}->put( $output ) if $self->_wheel_exists( $route_id );
  undef;
}

sub _send_output {
  $_[OBJECT]->send_output( @_[ARG0..$#_] );
  undef;
}

##########################
# Auth subsystem methods #
##########################

sub _auth_client {
  my ($kernel,$self,$wheel_id) = @_[KERNEL,OBJECT,ARG0];
  return unless $self->_wheel_exists( $wheel_id );

  my ($peeraddr,$peerport,$sockaddr,$sockport) = $self->connection_info( $wheel_id );

  $self->send_output( { command => 'NOTICE', params => [ 'AUTH', '*** Checking Ident' ] }, $wheel_id );
  $self->send_output( { command => 'NOTICE', params => [ 'AUTH', '*** Checking Hostname' ] }, $wheel_id );

  if ( $peeraddr !~ /^127\./ ) {
	my $response = $self->{resolver}->resolve( 
		event => '_got_hostname_response', 
		host => $peeraddr,
		context => { wheel => $wheel_id, peeraddress => $peeraddr },
		type => 'PTR' 
	);
	if ( $response ) {
		$kernel->yield( '_got_hostname_response' => $response );
	}
  } else {
  	$self->send_output( { command => 'NOTICE', params => [ 'AUTH', '*** Found your hostname' ] }, $wheel_id );
	$self->{wheels}->{ $wheel_id }->{auth}->{hostname} = 'localhost';
	$self->yield( '_auth_done' => $wheel_id );
  }
  POE::Component::Client::Ident::Agent->spawn( 
		PeerAddr => $peeraddr, 
		PeerPort => $peerport, 
		SockAddr => $sockaddr,
	        SockPort => $sockport, 
		BuggyIdentd => 1, 
		TimeOut => 10,
		Reference => $wheel_id 
  );
  undef;
}

sub _auth_done {
  my ($kernel,$self,$wheel_id) = @_[KERNEL,OBJECT,ARG0];

  return unless $self->_wheel_exists( $wheel_id );
  if ( defined ( $self->{wheels}->{ $wheel_id }->{auth}->{ident} ) and defined ( $self->{wheels}->{ $wheel_id }->{auth}->{hostname} ) ) {
	$self->_send_event( $self->{prefix} . 'auth_done' => $wheel_id => { 
		ident    => $self->{wheels}->{ $wheel_id }->{auth}->{ident},
   	        hostname => $self->{wheels}->{ $wheel_id }->{auth}->{hostname} } )
		unless ( $self->{wheels}->{ $wheel_id }->{auth}->{done} );
	$self->{wheels}->{ $wheel_id }->{auth}->{done}++;
  }
  undef;
}

sub _got_hostname_response {
    my ($kernel,$self) = @_[KERNEL,OBJECT];
    my $response = $_[ARG0];
    my $wheel_id = $response->{context}->{wheel};

    return unless $self->_wheel_exists( $wheel_id );
    if ( defined $response->{response} ) {
      my @answers = $response->{response}->answer();

      if ( scalar @answers == 0 ) {
	# Send NOTICE to client of failure.
	$self->send_output( { command => 'NOTICE', params => [ 'AUTH', "*** Couldn\'t look up your hostname" ] }, $wheel_id ) unless defined $self->{wheels}->{ $wheel_id }->{auth}->{hostname};
	$self->{wheels}->{ $wheel_id }->{auth}->{hostname} = '';
	$self->yield( '_auth_done' => $wheel_id );
      }

      foreach my $answer (@answers) {
	my $context = $response->{context};
	$context->{hostname} = $answer->rdatastr();
	if ( $context->{hostname} =~ /\.$/ ) {
	   chop $context->{hostname};
	}
	my $query = $self->{resolver}->resolve( 
		event => '_got_ip_response', 
		host => $answer->rdatastr(), 
		context => $context, 
		type => 'A' 
	);
	if ( defined $query ) {
	   $self->yield( '_got_ip_response' => $query );
	}
      }
    } else {
	# Send NOTICE to client of failure.
	$self->send_output( { command => 'NOTICE', params => [ 'AUTH', "*** Couldn\'t look up your hostname" ] }, $wheel_id ) unless defined $self->{wheels}->{ $wheel_id }->{auth}->{hostname};
	$self->{wheels}->{ $wheel_id }->{auth}->{hostname} = '';
	$self->yield( '_auth_done' => $wheel_id );
    }
    undef;
}

sub _got_ip_response {
    my ($kernel,$self) = @_[KERNEL,OBJECT];
    my $response = $_[ARG0];
    my $wheel_id = $response->{context}->{wheel};

    return unless $self->_wheel_exists( $wheel_id );
    if ( defined $response->{response} ) {
      my @answers = $response->{response}->answer();
      my $peeraddress = $response->{context}->{peeraddress};
      my $hostname = $response->{context}->{hostname};

      if ( scalar @answers == 0 ) {
	# Send NOTICE to client of failure.
	$self->send_output( { command => 'NOTICE', params => [ 'AUTH', "*** Couldn\'t look up your hostname" ] }, $wheel_id ) unless defined $self->{wheels}->{ $wheel_id }->{auth}->{hostname};
	$self->{wheels}->{ $wheel_id }->{auth}->{hostname} = '';
	$self->yield( '_auth_done' => $wheel_id );
      }

      foreach my $answer (@answers) {
	if ( $answer->rdatastr() eq $peeraddress and !defined $self->{wheels}->{ $wheel_id }->{auth}->{hostname} ) {
	   $self->send_output( { command => 'NOTICE', params => [ 'AUTH', '*** Found your hostname' ] }, $wheel_id ) unless $self->{wheels}->{ $wheel_id }->{auth}->{hostname};
	   $self->{wheels}->{ $wheel_id }->{auth}->{hostname} = $hostname;
	   $self->yield( '_auth_done' => $wheel_id );
	   return;
	} else {
	   $self->send_output( { command => 'NOTICE', params => [ 'AUTH', '*** Your forward and reverse DNS do not match' ] }, $wheel_id ) unless $self->{wheels}->{ $wheel_id }->{auth}->{hostname};
	   $self->{wheels}->{ $wheel_id }->{auth}->{hostname} = '';
	   $self->yield( '_auth_done' => $wheel_id );
	}
      }
    } else {
	# Send NOTICE to client of failure.
	$self->send_output( { command => 'NOTICE', params => [ 'AUTH', "*** Couldn\'t look up your hostname" ] }, $wheel_id ) unless $self->{wheels}->{ $wheel_id }->{auth}->{hostname};
	$self->{wheels}->{ $wheel_id }->{auth}->{hostname} = '';
	$self->yield( '_auth_done' => $wheel_id );
    }
    undef;
}

sub ident_agent_reply {
  my ($kernel,$self,$ref,$opsys,$other) = @_[KERNEL,OBJECT,ARG0,ARG1,ARG2];
  my $wheel_id = $ref->{Reference};

  if ( $self->_wheel_exists( $wheel_id ) ) {
      my $ident = '';
      if ( uc ( $opsys ) ne 'OTHER' ) {
	$ident = $other;
      }
      $self->send_output( { command => 'NOTICE', params => [ 'AUTH', "*** Got Ident response" ] }, $wheel_id );
      $self->{wheels}->{ $wheel_id }->{auth}->{ident} = $ident;
      $self->yield( '_auth_done' => $wheel_id );
  }
  undef;
}

sub ident_agent_error {
  my ($kernel,$self,$ref,$error) = @_[KERNEL,OBJECT,ARG0,ARG1];
  my $wheel_id = $ref->{Reference};

  if ( $self->_wheel_exists( $wheel_id ) ) {
      $self->send_output( { command => 'NOTICE', params => [ 'AUTH', "*** No Ident response" ] }, $wheel_id );
      $self->{wheels}->{ $wheel_id }->{auth}->{ident} = '';
      $self->yield( '_auth_done' => $wheel_id );
  }
  undef;
}

######################
# Connection methods #
######################

sub antiflood {
  my ($self,$wheel_id,$value) = splice @_, 0, 3;
  return unless $self->_wheel_exists( $wheel_id );
  return 0 unless $self->{antiflood};
  return $self->{wheels}->{ $wheel_id }->{antiflood} unless defined $value;
  unless ( $value ) {
    # Flush pending messages from that wheel
    while ( my $alarm_id = shift @{ $self->{wheels}->{ $wheel_id }->{alarm_ids} } ) {
      $poe_kernel->alarm_remove( $alarm_id );
      my $input = shift @{ $self->{wheels}->{ $wheel_id }->{msq} };
      if ( $input ) {
        my $event = $self->{prefix} . 'cmd_' . lc ( $input->{command} );
        $self->_send_event( $event => $wheel_id => $input );
      }
    }
  }
  $self->{wheels}->{ $wheel_id }->{antiflood} = $value;
}

sub compressed_link {
  my ($self,$wheel_id,$value,$cntr) = splice @_, 0, 4;
  return unless $self->{got_zlib};
  return unless $self->_wheel_exists( $wheel_id );
  return $self->{wheels}->{ $wheel_id }->{compress} unless defined $value;
  if ( $value ) {
	if ( $cntr ) {
	  $self->{wheels}->{ $wheel_id }->{wheel}->get_input_filter()->unshift( POE::Filter::Zlib::Stream->new() );
	$self->_send_event( $self->{prefix} . 'compressed_conn' => $wheel_id );
	} else {
	  $self->{wheels}->{ $wheel_id }->{compress_pending} = 1;
	}
  } else {
	$self->{wheels}->{ $wheel_id }->{wheel}->get_input_filter()->shift();
  }
  $self->{wheels}->{ $wheel_id }->{compress} = $value;
}

sub disconnect {
  my ($self,$wheel_id,$string) = splice @_, 0, 3;
  return unless $wheel_id and $self->_wheel_exists( $wheel_id );
  $self->{wheels}->{ $wheel_id }->{disconnecting} = $string || 'Client Quit';
}

sub _disconnected {
  my ($self,$wheel_id,$errstr) = splice @_, 0, 3;
  return unless $wheel_id and $self->_wheel_exists( $wheel_id );
  my $conn = delete $self->{wheels}->{ $wheel_id };
  $poe_kernel->alarm_remove( $_ ) for ( $conn->{alarm}, @{ $conn->{alarm_ids} } );
  $self->_send_event( $self->{prefix} . 'disconnected' => $wheel_id => $errstr || 'Client Quit' );
  return 1;
}

sub connection_info {
  my ($self,$wheel_id) = splice @_, 0, 2;
  return unless $self->_wheel_exists( $wheel_id );
  return map { $self->{wheels}->{ $wheel_id }->{$_} } qw(peeraddr peerport sockaddr sockport);
}

sub _wheel_exists {
  my ($self,$wheel_id) = @_;
  return 0 unless $wheel_id and defined $self->{wheels}->{ $wheel_id };
  return 1;
}

sub _conn_flooded {
  my $self = shift;
  my $conn_id = shift || return;
  return unless $self->_wheel_exists( $conn_id );
  return $self->{wheels}->{ $conn_id }->{flooded};
}

######################
# Spoofed Client API #
######################



##################
# Access Control #
##################

sub add_denial {
  my $self = shift;
  my $netmask = shift || return;
  my $reason = shift || 'Denied';
  return unless $netmask->isa('Net::Netmask');
  $self->{denials}->{ $netmask } = { blk => $netmask, reason => $reason };
  return 1;
}
 
sub del_denial {
  my $self = shift;
  my $netmask = shift || return;
  return unless $netmask->isa('Net::Netmask');
  return unless $self->{denials}->{ $netmask };
  delete $self->{denials}->{ $netmask };
  return 1;
}

sub add_exemption {
  my $self = shift;
  my $netmask = shift || return;
  return unless $netmask->isa('Net::Netmask');
  $self->{exemptions}->{ $netmask } = $netmask unless $self->{exemptions}->{ $netmask };
  return 1;
}

sub del_exemption {
  my $self = shift;
  my $netmask = shift || return;
  return unless $netmask->isa('Net::Netmask');
  return unless $self->{exemptions}->{ $netmask };
  delete $self->{exemptions}->{ $netmask };
  return 1;
}

sub denied {
  my $self = shift;
  my $ipaddr = shift || return;
  return 0 if $self->exempted( $ipaddr );
  foreach my $mask ( keys %{ $self->{denials} } ) {
    return $self->{denials}->{ $mask }->{reason} if $self->{denials}->{ $mask }->{blk}->match($ipaddr);
  }
  return 0;
}

sub exempted {
  my $self = shift;
  my $ipaddr = shift || return;
  foreach my $mask ( keys %{ $self->{exemptions} } ) {
    return 1 if $self->{exemptions}->{ $mask }->match($ipaddr);
  }
  return 0;
}

##################
# Plugin methods #
##################

# accesses the plugin pipeline
sub pipeline {
  my ($self) = @_;
  $self->{PLUGINS} = POE::Component::Server::IRC::Pipeline->new($self)
    unless UNIVERSAL::isa($self->{PLUGINS}, 'POE::Component::Server::IRC::Pipeline');
  return $self->{PLUGINS};
}

# Adds a new plugin object
sub plugin_add {
  my ($self, $name, $plugin) = @_;
  my $pipeline = $self->pipeline;

  unless (defined $name and defined $plugin) {
    warn 'Please supply a name and the plugin object to be added!';
    return;
  }

  return $pipeline->push($name => $plugin);
}

# Removes a plugin object
sub plugin_del {
  my ($self, $name) = @_;

  unless (defined $name) {
    warn 'Please supply a name/object for the plugin to be removed!';
    return;
  }

  my $return = scalar $self->pipeline->remove($name);
  warn "$@\n" if $@;
  return $return;
}

# Gets the plugin object
sub plugin_get {
  my ($self, $name) = @_;  

  unless (defined $name) {
    warn 'Please supply a name/object for the plugin to be removed!';
    return;
  }

  return scalar $self->pipeline->get($name);
}

# Lists loaded plugins
sub plugin_list {
  my ($self) = @_;
  my $pipeline = $self->pipeline;
  my %return;

  for (@{ $pipeline->{PIPELINE} }) {
    $return{ $pipeline->{PLUGS}{$_} } = $_;
  }

  return \%return;
}

# Lists loaded plugins in order!
sub plugin_order {
  my ($self) = @_;
  return $self->pipeline->{PIPELINE};
}

# Lets a plugin register for certain events
sub plugin_register {
  my ($self, $plugin, $type, @events) = @_;
  my $pipeline = $self->pipeline;

  unless (defined $type and ($type eq 'SERVER' or $type eq 'USER')) {
    warn 'Type should be SERVER or USER!';
    return;
  }

  unless (defined $plugin) {
    warn 'Please supply the plugin object to register!';
    return;
  }

  unless (@events) {
    warn 'Please supply at least one event to register!';
    return;
  }

  for my $ev (@events) {
    if (ref($ev) and ref($ev) eq "ARRAY") {
      @{ $pipeline->{HANDLES}{$plugin}{$type} }{ map lc, @$ev } = (1) x @$ev;
    }
    else {
      $pipeline->{HANDLES}{$plugin}{$type}{lc $ev} = 1;
    }
  }

  return 1;
}

# Lets a plugin unregister events
sub plugin_unregister {
  my ($self, $plugin, $type, @events) = @_;
  my $pipeline = $self->pipeline;

  unless (defined $type and ($type eq 'SERVER' or $type eq 'USER')) {
    warn 'Type should be SERVER or USER!';
    return;
  }

  unless (defined $plugin) {
    warn 'Please supply the plugin object to register!';
    return;
  }

  unless (@events) {
    warn 'Please supply at least one event to unregister!';
    return;
  }

  for my $ev (@events) {
    if (ref($ev) and ref($ev) eq "ARRAY") {
      for my $e (map lc, @$ev) {
        unless (delete $pipeline->{HANDLES}{$plugin}{$type}{$e}) {
          warn "The event '$e' does not exist!";
          next;
        }
      }
    }
    else {
      $ev = lc $ev;
      unless (delete $pipeline->{HANDLES}{$plugin}{$type}{$ev}) {
        warn "The event '$ev' does not exist!";
        next;
      }
    }
  }

  return 1;
}

# Process an input event for plugins
sub _plugin_process {
  my ($self, $type, $event, @args) = @_;
  my $pipeline = $self->pipeline;

  $event = lc $event;
  my $prefix = $self->{prefix};
  $event =~ s/^\Q$prefix\E//;

  my $sub = ($type eq 'SERVER' ? "IRCD" : "U") . "_$event";
  my $return = PCSI_EAT_NONE;
  my $our_ret = $return;

  if ( $self->can($sub) ) {
  	$our_ret = $self->$sub( $self, @args );
  } elsif ( $self->can('_default') ) {
	$our_ret = $self->_default( $self, $sub, @args );
  }

  return $return if $our_ret == PCSI_EAT_PLUGIN;
  $return = PCSI_EAT_ALL if $our_ret == PCSI_EAT_CLIENT;
  return PCSI_EAT_ALL if $our_ret == PCSI_EAT_ALL;

  for my $plugin (@{ $pipeline->{PIPELINE} }) {
    next
      unless $pipeline->{HANDLES}{$plugin}{$type}{$event}
      or $pipeline->{HANDLES}{$plugin}{$type}{all};

    my $ret = PCSI_EAT_NONE;

    eval { $ret = $plugin->$sub($self, @args) };
    warn "$sub call failed with $@\n" if $@ and $self->{plugin_debug} and $plugin->can($sub);
    eval { $ret = $plugin->_default($self, $sub, @args) } if $@;
    warn "_default call failed with $@\n" if $@ and $self->{plugin_debug};

    return $return if $ret == PCSI_EAT_PLUGIN;
    $return = PCSI_EAT_ALL if $ret == PCSI_EAT_CLIENT;
    return PCSI_EAT_ALL if $ret == PCSI_EAT_ALL;
  }

  return $return;
}  

1;
__END__
