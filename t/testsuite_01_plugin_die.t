use Test::More tests => 7;

{
  package PCI::Test::Plugin;
  use POE::Component::IRC::Plugin qw(:ALL);

  sub new {
    return bless { @_[1..$#_] }, $_[0];
  }

  sub PCI_register {
    die "DIE TEST! In 'PCI_register'" if $_[0]->{die};
    $_[1]->plugin_register( $_[0], 'SERVER', qw(all) );
    return 1;
  }

  sub PCI_unregister {
    return 1;
  }

  sub _default {
    die "DIE TEST! In '_default'" if $_[0]->{die};
    return PCI_EAT_NONE;
  }

  sub _die_test {
    my $self = shift;
    $self->{die} = shift;
  }

  sub S_test_plugin_die {
    die "Testing eval is protecting us";
    return PCI_EAT_NONE;
  }

}

BEGIN { use_ok('POE::Component::IRC') };
use POE;

my $self = POE::Component::IRC->spawn( plugin_debug => 1 );

isa_ok ( $self, 'POE::Component::IRC' );

POE::Session->create(
	inline_states => { _start => \&test_start, },
	package_states => [
	  'main' => [ qw(irc_plugin_add irc_plugin_del irc_test_plugin_die) ],
	],
);

$poe_kernel->run();
exit 0;

sub test_start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];

  $self->yield( 'register' => 'all' );

  my $plugin = PCI::Test::Plugin->new( 'die' => 1 );
  isa_ok ( $plugin, 'PCI::Test::Plugin' );
  
  $heap->{counter} = 1;
  unless ( $self->plugin_add( 'TestPlugin' => $plugin ) ) {
	pass( 'plugin_add' );
	$plugin->_die_test(0);
	$self->plugin_add( 'TestPlugin' => $plugin );
  }

  undef;
}

sub irc_plugin_add {
  my ($kernel,$heap,$desc,$plugin) = @_[KERNEL,HEAP,ARG0,ARG1];

  isa_ok ( $plugin, 'PCI::Test::Plugin' );
  $self->send_event( 'irc_test_plugin_die', "DIE! DIE! DIE!" );
  undef;
}

sub irc_test_plugin_die {
  pass "Test Plugin Die";
  unless ( $self->plugin_del( 'TestPlugin' ) ) {
  	fail( 'plugin_del' );
  	$self->yield( 'unregister' => 'all' );
  	$self->yield( 'shutdown' );
  }
  undef;
}

sub irc_plugin_del {
  my ($kernel,$heap,$desc,$plugin) = @_[KERNEL,HEAP,ARG0,ARG1];

  isa_ok ( $plugin, 'PCI::Test::Plugin' );
  $heap->{counter}--;
  if ( $heap->{counter} <= 0 ) {
    $self->yield( 'unregister' => 'all' );
    $self->yield( 'shutdown' );
  } else {
    unless ( $self->plugin_add( 'TestPlugin' => $plugin ) ) {
	fail( 'plugin_add' );
  	$self->yield( 'unregister' => 'all' );
  	$self->yield( 'shutdown' );
    }
  }
  undef;
}
