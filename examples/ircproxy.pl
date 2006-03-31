use strict;
use warnings;
use Socket;
use Getopt::Long;

use POE qw(Component::IRC Component::IRC::Plugin::Proxy);

my $nick;
my $user;
my $server;
my $port;
my $ircname;
my $bindaddr;
my $bindport;
my $password;

GetOptions(
"address=s" => \$bindaddr,
"bindport=s" => \$bindport,
"password=s" => \$password,
"nick=s" => \$nick,
"server=s" => \$server,
"user=s" => \$user,
"port=s" => \$port,
"ircname=s" => \$ircname,
);

die "Please specify a nickname and a servername\n" unless ( $nick and $server );

my $poco = POE::Component::IRC->spawn(Nick => $nick, Server => $server, Port => $port, Ircname => $ircname, Username => $user);

POE::Session->create(
  package_states => [ 
	'main' => [ qw(_start _default irc_proxy_service irc_proxy_authed irc_proxy_close) ],
  ],
  heap => { irc => $poco },
  options => { trace => 0 },
);

$poe_kernel->run();
exit 0;

sub _start {
  my ($kernel,$heap) = @_[KERNEL,HEAP];
  my $irc = $heap->{irc};
  $irc->yield( register => 'all' );
  $heap->{proxy} = POE::Component::IRC::Plugin::Proxy->new( bindaddress => $bindaddr, bindport => $bindport, password => $password );
  $irc->plugin_add( 'Proxy' => $heap->{proxy} );
  $irc->yield( connect => { } );
  undef;
}

sub _default {
  my ($event) = $_[ARG0];
  my (@args) = @{ $_[ARG1] };
  my (@output) = ( "$event: " );

  foreach my $arg ( @args ) {
        if ( ref($arg) eq 'ARRAY' ) {
                push( @output, "[" . join(" ,", @$arg ) . "]" );
        } else {
                push ( @output, "'$arg'" );
        }
  }
  print STDOUT join(', ', @output, "\n" );
  undef;
}

sub irc_proxy_service {
  my ($kernel,$heap,$mysockaddr) = @_[KERNEL,HEAP,ARG0];

  my ($port, $myaddr) = sockaddr_in($mysockaddr);
                   printf "Connect to %s [%s]:[%s]\n",
                      scalar gethostbyaddr($myaddr, AF_INET),
                      inet_ntoa($myaddr), $port;
  undef;
}

sub irc_proxy_authed {
  my ($kernel,$heap) = @_[KERNEL,HEAP];
  $heap->{irc}->yield( ctcp => $_ => 'ACTION has attached' ) for $heap->{proxy}->current_channels();
  undef;
}

sub irc_proxy_close {
  my ($kernel,$heap) = @_[KERNEL,HEAP];
  $heap->{irc}->yield( ctcp => $_ => 'ACTION has detached' ) for $heap->{proxy}->current_channels();
  undef;
}
