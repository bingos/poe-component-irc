use 5.006;
use strict;
use inc::Module::Install;

print <<NOTICE;

---------------------------------------------------------------
A lot of the tests make use of the loopback interface. If this
is firewalled then these tests will fail. 
---------------------------------------------------------------

NOTICE

_no_dns() unless can_use('POE::Component::Client::DNS',0.99);

name 'POE-Component-IRC';
license 'perl';
author 'Chris Williams <chris@bingosnet.co.uk>';
version_from 'lib/POE/Component/IRC.pm';
abstract_from 'lib/POE/Component/IRC.pm';
perl_version '5.006';
requires 'POE'    => 0.3202;
requires 'POE::Component::Pluggable' => '1.24';
requires 'POE::Wheel::SocketFactory' => 0;
requires 'POE::Wheel::ReadWrite' => 0;
requires 'POE::Driver::SysRW' => 0;
requires 'POE::Filter::Line' => 0;
requires 'POE::Filter::Stream' => 0;
requires 'POE::Filter::Stackable' => 0;
requires 'POE::Filter::IRCD' => 1.7;
requires 'Encode' => 0;
requires 'Encode::Guess' => 0;
test_requires 'Test::More' => '0.47';
tests_recursive;
author_tests 'xt';
clean_files 'README.send Changes.resume followtail logger_test';
auto_provides;
githubmeta;
WriteAll();
exit 0;

sub _no_dns {
  print <<NO_DNS;

----------------------------------------------------------------
Hmmm. POE::Component::Client::DNS 0.99 isn't installed. Its use
is recommended but not necessary. Consider installing it. Thanks
----------------------------------------------------------------

NO_DNS
  return;
}
