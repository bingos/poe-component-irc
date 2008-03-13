use Test::More tests => 11;
BEGIN { use_ok('POE::Component::IRC::State') };
BEGIN { use_ok('POE::Component::IRC::Plugin::PlugMan') };

use POE;

my $self = POE::Component::IRC::State->spawn( );

isa_ok ( $self, 'POE::Component::IRC::State' );

POE::Session->create(
	inline_states => { _start => \&test_start, },
	package_states => [
	  'main' => [ qw(irc_plugin_add irc_plugin_del) ],
	],
	options => { trace => 0 },
);

$poe_kernel->run();
exit 0;

sub test_start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];

  $self->yield( 'register' => 'all' );

  my $plugin = POE::Component::IRC::Plugin::PlugMan->new( debug => 0 );
  isa_ok ( $plugin, 'POE::Component::IRC::Plugin::PlugMan' );
  
  unless ( $self->plugin_add( 'TestPlugin' => $plugin ) ) {
	fail( 'plugin_add' );
  	$self->yield( 'unregister' => 'all' );
  	$self->yield( 'shutdown' );
  }

  undef;
}

{
    package MyPlugin;
    use POE::Component::IRC::Plugin qw( :ALL );
    sub new {
        return bless { @_[1..$#_] }, $_[0];
    }

    sub PCI_register {
        $_[1]->plugin_register( $_[0], 'SERVER', qw(all) );
        return 1;
    }

    sub PCI_unregister {
        return 1;
    }

    sub _default {
        return PCI_EAT_NONE;
    }
    
}

sub irc_plugin_add {
  my ($kernel,$heap,$desc,$plugin) = @_[KERNEL,HEAP,ARG0,ARG1];
  return unless $desc eq "TestPlugin";

  isa_ok ( $plugin, 'POE::Component::IRC::Plugin::PlugMan' );

  ok( $plugin->load( 'Test1', 'POE::Component::IRC::Test::Plugin' ), "PlugMan_load" );
  ok( $plugin->reload( 'Test1' ), "PlugMan_reload" );
  ok( $plugin->unload( 'Test1' ), "PlugMan_unload" );
  
  ok( $plugin->load( 'Test2', MyPlugin->new() ), "Test2_load" );
  ok( $plugin->unload( 'Test2' ), "Test2_unload" );
  
  unless ( $self->plugin_del( 'TestPlugin' ) ) {
  	fail( 'plugin_del' );
  	$self->yield( 'unregister' => 'all' );
  	$self->yield( 'shutdown' );
  }
  undef;
}

sub irc_plugin_del {
  my ($kernel,$heap,$desc,$plugin) = @_[KERNEL,HEAP,ARG0,ARG1];
  return unless $desc eq "TestPlugin";

  isa_ok ( $plugin, 'POE::Component::IRC::Plugin::PlugMan' );
  
  $self->yield( 'unregister' => 'all' );
  $self->yield( 'shutdown' );
  undef;
}
