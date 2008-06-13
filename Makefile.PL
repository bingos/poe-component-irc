use 5.006;
use strict;
use inc::Module::Install;

my $GOT_DNS;

BEGIN {
   $GOT_DNS = 0;
   eval {
	require POE::Component::Client::DNS;
	$GOT_DNS = 1 if $POE::Component::Client::DNS::VERSION >= 0.99;
   };
}

print <<NOTICE;

---------------------------------------------------------------
POE::Component::IRC now features an online test as part of the
testsuite. Whilst I have tried to make it as robust as I can
the last test may take up to 40 seconds or so to complete.
Please be patient while it does it's thing.
---------------------------------------------------------------

---------------------------------------------------------------
A lot of the tests make use of the loopback interface. If this
is firewalled then these tests will fail. 
---------------------------------------------------------------

NOTICE

_no_dns() unless $GOT_DNS;

name 'POE-Component-IRC';
license 'perl';
author 'Chris Williams <chris@bingosnet.co.uk>';
version_from 'lib/POE/Component/IRC.pm';
abstract_from 'lib/POE/Component/IRC.pm';
build_requires 'Test::More' => '0.47';
perl_version '5.006';
requires 'POE'    => 0.3202;
requires 'POE::Component::Pluggable' => '1.08';
requires 'POE::Wheel::SocketFactory' => 0;
requires 'POE::Wheel::ReadWrite' => 0;
requires 'POE::Driver::SysRW' => 0;
requires 'POE::Filter::Line' => 0;
requires 'POE::Filter::Stream' => 0;
requires 'POE::Filter::Stackable' => 0;
requires 'POE::Filter::IRCD' => 1.7;
requires 'Encode' => 0;
requires 'Encode::Guess' => 0;
tests 't/*.t t/*/*.t t/*/*/*.t';
author_tests 'xt';
clean_files 'README.send Changes.resume followtail logger_test';
WriteAll();
exit 0;

sub _no_dns {
  print <<NO_DNS;

----------------------------------------------------------------
Hmmm. POE::Component::Client::DNS 0.99 isn't installed. It's use
is recommended but not necessary. Consider installing it. Thanks
----------------------------------------------------------------

NO_DNS
  return;
}
