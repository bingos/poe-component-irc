use Test::More tests => 21;

BEGIN { use_ok('POE::Component::IRC::Test::Harness') };
BEGIN { use_ok('POE::Component::IRC::State') };

use POE qw(Wheel::SocketFactory);
use Socket;
use Data::Dumper;

my $ircd = POE::Component::IRC::Test::Harness->spawn( Alias => 'ircd', Auth => 0, AntiFlood => 0, Debug => 0 );
my $irc = POE::Component::IRC::State->spawn( options => { trace => 0 } );

isa_ok ( $ircd, 'POE::Component::IRC::Test::Harness' );
isa_ok ( $irc, 'POE::Component::IRC::State' );

POE::Session->create(
	inline_states => { _start => \&test_start, },
	package_states => [
	   'main' => [qw(_config_ircd 
			 _shutdown 
			 irc_registered 
			 irc_connected 
			 irc_001 
			 irc_whois 
			 irc_join
			 irc_chan_sync
			 irc_chan_mode
			 irc_mode
			 irc_error
			 irc_disconnected
	   )],
	],
	options => { trace => 0 },
);

$poe_kernel->run();
exit 0;

sub test_start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];

  my $wheel = POE::Wheel::SocketFactory->new(
	BindAddress => '127.0.0.1',
	BindPort => 0,
	SuccessEvent => '_fake_success',
	FailureEvent => '_fake_failure',
  );

  if ( $wheel ) {
	my $port = ( unpack_sockaddr_in( $wheel->getsockname ) )[0];
	$kernel->yield( '_config_ircd' => $port );
	$wheel = undef;
	$kernel->delay( '_shutdown' => 60 );
	return;
  }
  $kernel->yield('_shutdown');
  undef;
}

sub _shutdown {
  my ($kernel,$heap) = @_[KERNEL,HEAP];
  $kernel->alarm_remove_all();
  $kernel->post( 'ircd' => 'shutdown' );
  $irc->yield( 'unregister' => 'all' );
  $irc->yield( 'shutdown' );
  undef;
}

sub _config_ircd {
  my ($kernel,$heap,$port) = @_[KERNEL,HEAP,ARG0];
  $kernel->post ( 'ircd' => 'add_i_line' );
  $kernel->post ( 'ircd' => 'add_listener' => { Port => $port } );
  $irc->yield( 'register' => 'all' );
  $irc->yield( connect => { nick => 'TestBot',
        server => '127.0.0.1',
        port => $port,
        ircname => 'Test test bot',
  } );
  undef;
}

sub irc_registered {
  my ($kernel,$object) = @_[KERNEL,ARG0];
  isa_ok( $object, 'POE::Component::IRC::State' );
  undef;
}

sub irc_connected {
  pass( "Connected" );
  undef;
}

sub irc_001 {
  my ($kernel,$sender,$text) = @_[KERNEL,SENDER,ARG1];
  my $ircobj = $sender->get_heap();
  pass( 'connect' );
  ok( $ircobj->server_name() eq 'poco.server.irc', "Server Name Test" );
  ok( $ircobj->nick_name() eq 'TestBot', "Nick Name Test" );
  $ircobj->yield( 'whois' => 'TestBot' );
  undef;
}

sub irc_whois {
  my ($kernel,$sender,$whois) = @_[KERNEL,SENDER,ARG0];
  ok( $whois->{nick} eq 'TestBot', "Whois hash test" );
  $sender->get_heap()->yield( 'join' => '#testchannel' );
  undef;
}

sub irc_join {
  my ($kernel,$sender,$who,$where) = @_[KERNEL,SENDER,ARG0,ARG1];
  my $nick = ( split /!/, $who )[0];
  my $object = $sender->get_heap();
  ok( $nick eq $object->nick_name(), "JOINER Test" );
  ok( $where eq '#testchannel', "Joined Channel Test" );
  #$object->yield( 'quit' );
  undef;
}

sub irc_chan_sync {
  my ($sender,$channel) = @_[SENDER,ARG0];
  my $object = $sender->get_heap();
  my $mynick = $object->nick_name();
  my ($occupant) = $object->channel_list($channel);
  ok( $occupant eq 'TestBot', "Channel Occupancy Test" );
  ok( !$object->is_channel_mode_set( $channel, 't' ), "Channel Mode Set" );
  ok( $object->is_channel_member($channel, $mynick ), "Is Channel Member" );
  ok( $object->is_channel_operator($channel, $mynick ), "Is Channel Operator" );
  ok( $object->ban_mask( $channel, $mynick ), "Ban Mask Test" );
  $object->yield( 'mode', $channel, '+nt' );
  undef;
}

sub irc_chan_mode {
  my ($sender,$who,$channel,$mode) = @_[SENDER,ARG0,ARG1,ARG2];
  my $object = $sender->get_heap();
  $mode =~ s/\+//g;
  ok( $object->is_channel_mode_set( $channel, $mode ), "Channel Mode Set: $mode" );
  undef;
}

sub irc_mode {
  my $object = $_[SENDER]->get_heap();
  warn "# Waiting 3 seconds for the dust to settle\n";
  $object->delay( [ 'quit' ], 3 );
  undef;
}

sub irc_error {
  pass( "irc_error" );
  undef;
}

sub irc_disconnected {
  pass( "irc_disconnected" );
  $poe_kernel->yield( '_shutdown' );
  undef;
}
