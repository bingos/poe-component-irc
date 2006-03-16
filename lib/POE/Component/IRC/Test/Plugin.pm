package POE::Component::IRC::Test::Plugin;

use strict;
use warnings;
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

1;
