use Test::More tests => 41;

BEGIN { use_ok('POE::Component::IRC::Test::Harness') };
BEGIN { use_ok('POE::Component::IRC') };

use POE qw(Wheel::SocketFactory);
use Socket;
use Data::Dumper;

my $ircd = POE::Component::IRC::Test::Harness->spawn( Alias => 'ircd', Auth => 0, AntiFlood => 0, Debug => 0 );
my $irc = POE::Component::IRC->spawn( options => { trace => 0 } );

isa_ok ( $ircd, 'POE::Component::IRC::Test::Harness' );
isa_ok ( $irc, 'POE::Component::IRC' );

POE::Session->create(
	inline_states => { _start => \&test_start, },
	package_states => [
	   'main' => [qw(_config_ircd 
			 _shutdown 
			 _default
			 irc_registered 
			 irc_connected 
			 irc_001 
			 irc_391
			 irc_whois 
			 irc_join
			 irc_isupport
			 irc_error
			 irc_disconnected
			 irc_shutdown
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
  isa_ok( $object, 'POE::Component::IRC' );
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
  ok( $ircobj->session_alias() eq "$ircobj", "Alias Test" );
  $ircobj->yield( 'time' );
  $ircobj->yield( 'whois' => 'TestBot' );
  undef;
}

sub irc_391 {
  my ($sender,$time) = @_[SENDER,ARG1];
  pass( "Got the time, baby" );
  warn "# $time\n";
  undef;
}

sub irc_isupport {
  my $isupport = $_[ARG0];
  isa_ok( $isupport, 'POE::Component::IRC::Plugin::ISupport' );
  ok( $isupport->isupport('NETWORK') eq 'poconet', "ISupport Network" );
  ok( $isupport->isupport('CASEMAPPING') eq 'rfc1459', "ISupport Casemapping" );
  foreach my $isupp ( qw(MAXCHANNELS MAXBANS MAXTARGETS NICKLEN TOPICLEN KICKLEN CHANTYPES PREFIX CHANMODES) ) {
    ok( $isupport->isupport($isupp), "Testing $isupp" );
  }
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
  $object->yield( 'quit' );
  undef;
}

sub irc_error {
  pass( "irc_error" );
  undef;
}

sub irc_shutdown {
  pass( "irc_shutdown" );
  undef;
}

sub irc_disconnected {
  pass( "irc_disconnected" );
  $poe_kernel->yield( '_shutdown' );
  undef;
}

sub _default {
  my ($event,$parms) = @_[ARG0,ARG1];
  return 0 unless $event =~ /^irc_(002|003|004|422|251|255|311|312|317|318|353|366)$/;
  pass( "$event" );
  undef;
}
