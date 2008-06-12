use strict;
use warnings;
use Test::More tests => 3;
use POE;
use POE::Component::IRC;
use POE::Component::IRC::Plugin::CTCP;

my $irc = POE::Component::IRC->spawn( plugin_debug => 1 );

POE::Session->create(
    package_states => [
        main => [ qw(_start irc_plugin_add irc_plugin_del) ],
    ],
);

$poe_kernel->run();

sub _start {
    $DB::single=2;
    $irc->yield(register => 'all');

    my $plugin = POE::Component::IRC::Plugin::CTCP->new();
    isa_ok($plugin, 'POE::Component::IRC::Plugin::CTCP');

    $DB::single=2;
    if (!$irc->plugin_add('TestPlugin', $plugin)) {
        fail('plugin_add failed');
        $irc->yield('shutdown');
    }
}

sub irc_plugin_add {
    my ($name, $plugin) = @_[ARG0, ARG1];
    return if $name ne 'TestPlugin';

    isa_ok($plugin, 'POE::Component::IRC::Plugin::CTCP');
  
    if (!$irc->plugin_del('TestPlugin') ) {
        fail('plugin_del failed');
        $irc->yield('shutdown');
    }
}

sub irc_plugin_del {
    my ($name, $plugin) = @_[ARG0, ARG1];
    return if $name ne 'TestPlugin';

    isa_ok($plugin, 'POE::Component::IRC::Plugin::CTCP');
    $irc->yield('shutdown');
}
