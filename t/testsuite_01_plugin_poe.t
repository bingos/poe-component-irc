use Test::More tests => 15;
use POE;

{
  package PCI::Test::Plugin::POE;
  use POE;
  use POE::Component::IRC::Plugin qw(:ALL);

  sub new {
    return bless { @_[1..$#_] }, $_[0];
  }

  sub PCI_register {
    my ($self,$irc) = @_;
    die "DIE TEST! In 'PCI_register'\n" if $self->{die};
    $irc->plugin_register( $self, 'SERVER', qw(all) );
    $self->{session_id} = POE::Session->create(
	object_states => [ 
	   $self => [ qw(_start _shutdown _stop) ],
	],
    )->ID();
    return 1;
  }

  sub PCI_unregister {
    my $self = shift;
    $poe_kernel->call( $self->{session_id}, '_shutdown' );
    return 1;
  }

  sub _default {
    die "DIE TEST! In '_default'\n" if $_[0]->{die};
    return PCI_EAT_NONE;
  }

  sub _die_test {
    my $self = shift;
    $self->{die} = shift;
  }

  sub S_test_plugin_die {
    die "Testing eval is protecting us\n";
    return PCI_EAT_NONE;
  }

  sub _start {
    my ($kernel,$self,$session) = @_[KERNEL,OBJECT,SESSION];
    warn "Session: ", $session->ID(), " started\n" if $self->{debug};
    $self->{session_id} = $session->ID();
    $kernel->refcount_increment( $self->{session_id}, __PACKAGE__ );
    undef;
  }

  sub _stop {
    warn "Session: ", $_[SESSION]->ID(), " stopped\n" if $_[OBJECT]->{debug};
    undef;
  }

  sub _shutdown {
    my ($kernel,$self) = @_[KERNEL,OBJECT];
    $kernel->alarm_remove_all();
    $kernel->refcount_decrement( $self->{session_id}, __PACKAGE__ );
    undef;
  }

}

BEGIN { use_ok('POE::Component::IRC') };

my $self = POE::Component::IRC->spawn( plugin_debug => 1 );

isa_ok ( $self, 'POE::Component::IRC' );

POE::Session->create(
	inline_states => { _start => \&test_start, },
	package_states => [
	  'main' => [ qw(irc_plugin_add irc_plugin_del) ],
	],
);

$poe_kernel->run();
exit 0;

sub test_start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];

  $self->yield( 'register' => 'all' );

  my $plugin = PCI::Test::Plugin::POE->new( 'die' => 0 );
  isa_ok ( $plugin, 'PCI::Test::Plugin::POE' );
  
  $heap->{counter} = 6;
  unless ( $self->plugin_add( 'TestPlugin' => $plugin ) ) {
	fail( 'plugin_add' );
  	$self->yield( 'unregister' => 'all' );
  	$self->yield( 'shutdown' );
  }

  undef;
}

sub irc_plugin_add {
  my ($kernel,$heap,$desc,$plugin) = @_[KERNEL,HEAP,ARG0,ARG1];

  isa_ok ( $plugin, 'PCI::Test::Plugin::POE' );
  $plugin->_die_test(0);
  
  unless ( $self->plugin_del( 'TestPlugin' ) ) {
  	fail( 'plugin_del' );
  	$self->yield( 'unregister' => 'all' );
  	$self->yield( 'shutdown' );
  }
  undef;
}

sub irc_plugin_del {
  my ($kernel,$heap,$desc,$plugin) = @_[KERNEL,HEAP,ARG0,ARG1];

  isa_ok ( $plugin, 'PCI::Test::Plugin::POE' );
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
