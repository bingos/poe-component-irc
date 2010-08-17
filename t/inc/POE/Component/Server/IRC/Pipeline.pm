package POE::Component::Server::IRC::Pipeline;

use strict;
use warnings FATAL => 'all';

our $VERSION = '1.20';


sub new {
  my ($class, $irc) = @_;

  return bless {
    PLUGS => {},
    PIPELINE => [],
    HANDLES => {},
    IRC => $irc,
  }, $class;
}


sub push {
  my ($self, $alias, $plug) = @_;
  $@ = "Plugin named '$alias' already exists ($self->{PLUGS}{$alias})", return
    if $self->{PLUGS}{$alias};

  my $return;

  eval { $return = $plug->PCSI_register($self->{IRC}) };

  if ($return) {
    push @{ $self->{PIPELINE} }, $plug;
    $self->{PLUGS}{$alias} = $plug;
    $self->{PLUGS}{$plug} = $alias;
    $self->{IRC}->yield(__send_event => $self->{IRC}->{prefix} . 'plugin_add' => $alias => $plug);
    return scalar @{ $self->{PIPELINE} };
  }
  else { return }
}


sub pop {
  my ($self) = @_;

  return unless @{ $self->{PIPELINE} };

  my $plug = pop @{ $self->{PIPELINE} };
  my $alias = delete $self->{PLUGS}{$plug};
  delete $self->{PLUGS}{$alias};
  delete $self->{HANDLES}{$plug};

  eval { $plug->PCSI_unregister($self->{IRC}) };
  $self->{IRC}->yield(__send_event => $self->{IRC}->{prefix} . 'plugin_del' => $alias, $plug);

  return wantarray() ? ($plug, $alias) : $plug;
}


sub unshift {
  my ($self, $alias, $plug) = @_;
  $@ = "Plugin named '$alias' already exists ($self->{PLUGS}{$alias}", return
    if $self->{PLUGS}{$alias};

  my $return;

  eval { $return = $plug->PCSI_register($self->{IRC}) };

  if ($return) {
    unshift @{ $self->{PIPELINE} }, $plug;
    $self->{PLUGS}{$alias} = $plug;
    $self->{PLUGS}{$plug} = $alias;
    $self->{IRC}->yield(__send_event => $self->{IRC}->{prefix} . 'plugin_add' => $alias => $plug);
    return scalar @{ $self->{PIPELINE} };
  }
  else { return }

  return scalar @{ $self->{PIPELINE} };
}


sub shift {
  my ($self) = @_;

  return unless @{ $self->{PIPELINE} };

  my $plug = shift @{ $self->{PIPELINE} };
  my $alias = delete $self->{PLUGS}{$plug};
  delete $self->{PLUGS}{$alias};
  delete $self->{HANDLES}{$plug};

  eval { $plug->PCSI_unregister($self->{IRC}) };
  $self->{IRC}->yield(__send_event => $self->{IRC}->{prefix} . 'plugin_del' => $alias, $plug);

  return wantarray() ? ($plug, $alias) : $plug;
}


sub replace {
  my ($self, $old, $new_a, $new_p) = @_;
  my ($old_a, $old_p) = ref($old) ?
    ($self->{PLUGS}{$old}, $old) :
    ($old, $self->{PLUGS}{$old});

  $@ = "Plugin '$old_a' does not exist", return
    unless $old_p;

  delete $self->{PLUGS}{$old_p};
  delete $self->{PLUGS}{$old_a};
  delete $self->{HANDLES}{$old_p};
  eval { $old_p->PCSI_unregister($self->{IRC}) };
  $self->{IRC}->yield(__send_event => $self->{IRC}->{prefix} . 'plugin_del' => $old_a, $old_p);

  $@ = "Plugin named '$new_a' already exists ($self->{PLUGS}{$new_a}", return
    if $self->{PLUGS}{$new_a};

  my $return;

  eval { $return = $new_p->PCSI_register($self->{IRC}) };

  if ($return) {
    $self->{PLUGS}{$new_p} = $new_a;
    $self->{PLUGS}{$new_a} = $new_p;

    for (@{ $self->{PIPELINE} }) {
      $_ = $new_p, last if $_ == $old_p;
    }

    $self->{IRC}->yield(__send_event => $self->{IRC}->{prefix} . 'plugin_add' => $new_a => $new_p);
    return 1;
  }
  else { return }
}


sub remove {
  my ($self, $old) = @_;
  my ($old_a, $old_p) = ref($old) ?
    ($self->{PLUGS}{$old}, $old) :
    ($old, $self->{PLUGS}{$old});

  $@ = "Plugin '$old_a' does not exist", return
    unless $old_p;

  delete $self->{PLUGS}{$old_p};
  delete $self->{PLUGS}{$old_a};
  delete $self->{HANDLES}{$old_p};

  my $i = 0;
  for (@{ $self->{PIPELINE} }) {
    splice(@{ $self->{PIPELINE} }, $i, 1), last
      if $_ == $old_p;
    ++$i;
  }

  eval { $old_p->PCSI_unregister($self->{IRC}) };
  $self->{IRC}->yield(__send_event => $self->{IRC}->{prefix} . 'plugin_del' => $old_a, $old_p);

  return wantarray ? ($old_p, $old_a) : $old_p;
}


sub get {
  my ($self, $old) = @_;
  my ($old_a, $old_p) = ref($old) ?
    ($self->{PLUGS}{$old}, $old) :
    ($old, $self->{PLUGS}{$old});

  $@ = "Plugin '$old_a' does not exist", return
    unless $old_p;

  return wantarray ? ($old_p, $old_a) : $old_p;
}


sub get_index {
  my ($self, $old) = @_;
  my ($old_a, $old_p) = ref($old) ?
    ($self->{PLUGS}{$old}, $old) :
    ($old, $self->{PLUGS}{$old});

  $@ = "Plugin '$old_a' does not exist", return -1
    unless $old_p;

  my $i = 0;
  for (@{ $self->{PIPELINE} }) {
    return $i if $_ == $old_p;
    ++$i;
  }
}


sub insert_before {
  my ($self, $old, $new_a, $new_p) = @_;
  my ($old_a, $old_p) = ref($old) ?
    ($self->{PLUGS}{$old}, $old) :
    ($old, $self->{PLUGS}{$old});

  $@ = "Plugin '$old_a' does not exist", return
    unless $old_p;

  $@ = "Plugin named '$new_a' already exists ($self->{PLUGS}{$new_a}", return
    if $self->{PLUGS}{$new_a};

  my $return;

  eval { $return = $new_p->PCSI_register($self->{IRC}) };

  if ($return) {
    $self->{PLUGS}{$new_p} = $new_a;
    $self->{PLUGS}{$new_a} = $new_p;

    my $i = 0;
    for (@{ $self->{PIPELINE} }) {
      splice(@{ $self->{PIPELINE} }, $i, 0, $new_p), last
        if $_ == $old_p;
      ++$i;
    }

    $self->{IRC}->yield(__send_event => $self->{IRC}->{prefix} . 'plugin_add' => $new_a => $new_p);
    return 1;
  }
  else { return }
}


sub insert_after {
  my ($self, $old, $new_a, $new_p) = @_;
  my ($old_a, $old_p) = ref($old) ?
    ($self->{PLUGS}{$old}, $old) :
    ($old, $self->{PLUGS}{$old});

  $@ = "Plugin '$old_a' does not exist", return
    unless $old_p;

  $@ = "Plugin named '$new_a' already exists ($self->{PLUGS}{$new_a}", return
    if $self->{PLUGS}{$new_a};

  my $return;

  eval { $return = $new_p->PCSI_register($self->{IRC}) };

  if ($return) {
    $self->{PLUGS}{$new_p} = $new_a;
    $self->{PLUGS}{$new_a} = $new_p;

    my $i = 0;
    for (@{ $self->{PIPELINE} }) {
      splice(@{ $self->{PIPELINE} }, $i+1, 0, $new_p), last
        if $_ == $old_p;
      ++$i;
    }

    $self->{IRC}->yield(__send_event => $self->{IRC}->{prefix} . 'plugin_add' => $new_a => $new_p);
    return 1;
  }
  else { return }
}


sub bump_up {
  my ($self, $old, $diff) = @_;
  my $idx = $self->get_index($old);

  return -1 if $idx < 0;

  my $pipeline = $self->{PIPELINE};
  $diff ||= 1;

  my $pos = $idx - $diff;

  warn "$idx - $diff is negative, moving to head of the pipeline"
    if $pos < 0;

  splice(@$pipeline, $pos, 0, splice(@$pipeline, $idx, 1));

  return $pos;
}


sub bump_down {
  my ($self, $old, $diff) = @_;
  my $idx = $self->get_index($old);

  return -1 if $idx < 0;

  my $pipeline = $self->{PIPELINE};
  $diff ||= 1;

  my $pos = $idx + $diff;

  warn "$idx + $diff is too high, moving to back of the pipeline"
    if $pos >= @$pipeline;

  splice(@$pipeline, $pos, 0, splice(@$pipeline, $idx, 1));

  return $pos;
}


1;

__END__
