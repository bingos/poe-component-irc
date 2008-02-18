package POE::Component::IRC::Pipeline;

use strict;
use warnings;
use Carp;
use vars qw($VERSION);

$VERSION = '0.05';

sub new {
    my ($package, $irc) = @_;

    return bless {
        PLUGS    => {},
        PIPELINE => [],
        HANDLES  => {},
        IRC      => $irc,
        DEBUG    => $irc->{plugin_debug},
    }, $package;
}

sub push {
    my ($self, $alias, $plug) = @_;
    
    if ($self->{PLUGS}{$alias}) {
        carp "Plugin named '$alias' already exists ($self->{PLUGS}{$alias})";
        return;
    }

    if (!eval { $plug->PCI_register($self->{IRC}) } ) {
        carp $@;
        return;
    }

    push @{ $self->{PIPELINE} }, $plug;
    $self->{PLUGS}{$alias} = $plug;
    $self->{PLUGS}{$plug} = $alias;
    $self->{IRC}->yield(__send_event => irc_plugin_add => $alias => $plug);
    
    return scalar @{ $self->{PIPELINE} };
}

sub pop {
    my ($self) = @_;

    return if !scalar @{ $self->{PIPELINE} };

    my $plug = pop @{ $self->{PIPELINE} };
    my $alias = delete $self->{PLUGS}{$plug};
    delete $self->{PLUGS}{$alias};
    delete $self->{HANDLES}{$plug};

    eval { $plug->PCI_unregister($self->{IRC}) };
    carp $@ if $@;
    $self->{IRC}->yield(__send_event => irc_plugin_del => $alias, $plug);

    return wantarray() ? ($plug, $alias) : $plug;
}

sub unshift {
    my ($self, $alias, $plug) = @_;
  
    if ($self->{PLUGS}{$alias}) {
        $@ = "Plugin named '$alias' already exists ($self->{PLUGS}{$alias}";
        return;
    }
    
    if (!eval { $plug->PCI_register($self->{IRC}) } ) {
        carp "$@";
        return;
    }
    
    unshift @{ $self->{PIPELINE} }, $plug;
    $self->{PLUGS}{$alias} = $plug;
    $self->{PLUGS}{$plug} = $alias;
    $self->{IRC}->yield(__send_event => irc_plugin_add => $alias => $plug);

    return scalar @{ $self->{PIPELINE} };
}

sub shift {
    my ($self) = @_;

    return if !@{ $self->{PIPELINE} };

    my $plug = shift @{ $self->{PIPELINE} };
    my $alias = delete $self->{PLUGS}{$plug};
    delete $self->{PLUGS}{$alias};
    delete $self->{HANDLES}{$plug};

    eval { $plug->PCI_unregister($self->{IRC}) };
    carp "$@" if $@;
    
    $self->{IRC}->yield(__send_event => irc_plugin_del => $alias, $plug);
    return wantarray() ? ($plug, $alias) : $plug;
}


sub replace {
    my ($self, $old, $new_a, $new_p) = @_;
    
    my ($old_a, $old_p) = ref $old
        ? ($self->{PLUGS}{$old}, $old)
        : ($old, $self->{PLUGS}{$old});

    if (!$old_p) {
        carp "Plugin '$old_a' does not exist";
        return;
    }

    delete $self->{PLUGS}{$old_p};
    delete $self->{PLUGS}{$old_a};
    delete $self->{HANDLES}{$old_p};
    eval { $old_p->PCI_unregister($self->{IRC}) };
    carp "$@" if $@;
    $self->{IRC}->yield(__send_event => irc_plugin_del => $old_a, $old_p);

    if ($self->{PLUGS}{$new_a}) {
        carp "Plugin named '$new_a' already exists ($self->{PLUGS}{$new_a}";
        return;
    }
    
    if (!eval { $new_p->PCI_register($self->{IRC}) } ) {
        carp "$@";
        return;
    }

    $self->{PLUGS}{$new_p} = $new_a;
    $self->{PLUGS}{$new_a} = $new_p;

    for my $plugin (@{ $self->{PIPELINE} }) {
      $plugin = $new_p;
      last if $plugin == $old_p;
    }

    $self->{IRC}->yield(__send_event => irc_plugin_add => $new_a => $new_p);
    return 1;
}


sub remove {
    my ($self, $old) = @_;
  
    my ($old_a, $old_p) = ref $old
        ? ($self->{PLUGS}{$old}, $old)
        : ($old, $self->{PLUGS}{$old});

    if (!defined $old_p) {
        carp "Plugin '$old_a' does not exist";
        return;
    }

    delete $self->{PLUGS}{$old_p};
    delete $self->{PLUGS}{$old_a};
    delete $self->{HANDLES}{$old_p};

    for (my $i = 0; $i <= $#{ $self->{PIPELINE} }; $i++) {
        if ($self->{PIPELINE}->[$i] == $old_p) {
            splice @{ $self->{PIPELINE} }, $i, 1;
            last;
        }
    }

    eval { $old_p->PCI_unregister($self->{IRC}) };
    carp "$@" if $@;
    $self->{IRC}->yield(__send_event => irc_plugin_del => $old_a, $old_p);

    return wantarray ? ($old_p, $old_a) : $old_p;
}


sub get {
    my ($self, $old) = @_;

    my ($old_a, $old_p) = ref $old
        ? ($self->{PLUGS}{$old}, $old)
        : ($old, $self->{PLUGS}{$old});

    if (!defined $old_p) {
       carp "Plugin '$old_a' does not exist";
       return;
    }

    return wantarray ? ($old_p, $old_a) : $old_p;
}


sub get_index {
    my ($self, $old) = @_;
    
    my ($old_a, $old_p) = ref $old
        ? ($self->{PLUGS}{$old}, $old)
        : ($old, $self->{PLUGS}{$old});

    if (!defined $old_p) {
        carp "Plugin '$old_a' does not exist";
        return -1;
    }

    for (my $i = 0; $i <= $#{ $self->{PIPELINE} }; $i++) {
        return $i if $self->{PIPELINE}->[$i] == $old_p;
    }
    
    return -1;
}


sub insert_before {
    my ($self, $old, $new_a, $new_p) = @_;
  
    my ($old_a, $old_p) = ref $old
        ? ($self->{PLUGS}{$old}, $old)
        : ($old, $self->{PLUGS}{$old});

    if (!defined $old_p) {
        carp "Plugin '$old_a' does not exist";
        return;
    }

    if ($self->{PLUGS}{$new_a}) {
        carp "Plugin named '$new_a' already exists ($self->{PLUGS}{$new_a}";
        return;
    }

    if (!eval { $new_p->PCI_register($self->{IRC}) } ) {
        carp "$@";
        return;
    }

    $self->{PLUGS}{$new_p} = $new_a;
    $self->{PLUGS}{$new_a} = $new_p;

    for (my $i = 0; $i <= $#{ $self->{PIPELINE} }; $i++) {
      splice(@{ $self->{PIPELINE} }, $i, 0, $new_p);
      last if $self->{PIPELINE}->[$i] == $old_p;
    }

    $self->{IRC}->yield(__send_event => irc_plugin_add => $new_a => $new_p);
    return 1;
}


sub insert_after {
    my ($self, $old, $new_a, $new_p) = @_;
  
    my ($old_a, $old_p) = ref $old
        ? ($self->{PLUGS}{$old}, $old)
        : ($old, $self->{PLUGS}{$old});

    if (!defined $old_p) {
        carp "Plugin '$old_a' does not exist";
        return;
    }

    if ($self->{PLUGS}{$new_a}) {
        carp "Plugin named '$new_a' already exists ($self->{PLUGS}{$new_a}";
        return;
    }
    
    if (!eval { $new_p->PCI_register($self->{IRC}) } ) {
        carp $@;
        return;
    }

    $self->{PLUGS}{$new_p} = $new_a;
    $self->{PLUGS}{$new_a} = $new_p;

    for (my $i = 0; $i <= $#{ $self->{PIPELINE} }; $i++) {
      splice(@{ $self->{PIPELINE} }, $i+1, 0, $new_p);
      last if $self->{PIPELINE}->[$i] == $old_p;
    }

    $self->{IRC}->yield(__send_event => irc_plugin_add => $new_a => $new_p);
    return 1;
}


sub bump_up {
    my ($self, $old, $diff) = @_;
    my $idx = $self->get_index($old);

    return -1 if $idx < 0;

    my $pipeline = $self->{PIPELINE};
    $diff ||= 1;
    my $pos = $idx - $diff;
    if ($pos < 0) {
        carp "$idx - $diff is negative, moving to head of the pipeline";
    }

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
    if ($pos >= @$pipeline) {
        carp "$idx + $diff is too high, moving to back of the pipeline";
    }

    splice(@$pipeline, $pos, 0, splice(@$pipeline, $idx, 1));
    return $pos;
}

1;
__END__

=head1 NAME

POE::Component::IRC::Pipeline - the plugin pipeline for POE::Component::IRC.

=head1 SYNOPSIS

 use POE qw( Component::IRC );
 use POE::Component::IRC::Pipeline;
 use My::Plugin;

 my $irc = POE::Component::IRC->spawn;

 # the following operations are presented in pairs
 # the first is the general procedure, the second is
 # the specific way using the pipeline directly

 # to install a plugin
 $irc->plugin_add(mine => My::Plugin->new);
 $irc->pipeline->push(mine => My::Plugin->new);  

 # to remove a plugin
 $irc->plugin_del('mine');        # or the object
 $irc->pipeline->remove('mine');  # or the object

 # to get a plugin
 my $plug = $irc->plugin_get('mine');
 my $plug = $irc->pipeline->get('mine');

 # there are other very specific operations that
 # the pipeline offers, demonstrated here:

 # to get the pipeline object itself
 my $pipe = $irc->pipeline;

 # to install a plugin at the front of the pipeline
 $pipe->unshift(mine => My::Plugin->new);

 # to remove the plugin at the end of the pipeline
 my $plug = $pipe->pop;

 # to remove the plugin at the front of the pipeline
 my $plug = $pipe->shift;

 # to replace a plugin with another
 $pipe->replace(mine => newmine => My::Plugin->new);

 # to insert a plugin before another
 $pipe->insert_before(mine => newmine => My::Plugin->new);

 # to insert a plugin after another
 $pipe->insert_after(mine => newmine => My::Plugin->new);

 # to get the location in the pipeline of a plugin
 my $index = $pipe->get_index('mine');

 # to move a plugin closer to the front of the pipeline
 $pipe->bump_up('mine');

 # to move a plugin closer to the end of the pipeline
 $pipe->bump_down('mine');

=head1 DESCRIPTION

POE::Component::IRC::Pipeline defines the Plugin pipeline system for
POE::Component::IRC instances.  

=head1 METHODS

=over

=item C<new>

Takes one argument, the POE::Component::IRC object to attach to.

=item C<push>

Take two arguments, an alias for a plugin and the plugin object itself.
Adds the plugin to the end of the pipeline and registers it. If successful,
it returns the size of the pipeline.

 my $new_size = $pipe->push($name, $plug);

=item C<unshift>

Take two arguments, an alias for a plugin and the plugin object itself.
Adds the plugin to the beginning of the pipeline and registers it.
This will yield an 'irc_plugin_add' event.  If successful, it returns the
size of the pipeline.

 my $new_size = $pipe->push($name, $plug);

=item C<replace>

Take three arguments, the old plugin or its alias, an alias for the new plugin
and the new plugin object itself. Removes the old plugin (yielding an
'irc_plugin_del' event) and replaces it with the new plugin.This will yield an
'irc_plugin_add' event. If successful, it returns a true value.

 my $success = $pipe->replace($name, $new_name, $new_plug);
 my $success = $pipe->replace($plug, $new_name, $new_plug);

=item C<insert_before>

Takes three arguments, the plugin that is relative to the operation, an alias
for the new plugin and the new plugin object itself. The new plugin is placed
just prior to the other plugin in the pipeline. If successful, it returns a
true value.

 my $success = $pipe->insert_before($name, $new_name, $new_plug);
 my $success = $pipe->insert_before($plug, $new_name, $new_plug);

=item C<insert_after>

Takes three arguments, the plugin that is relative to the operation, an alias
for the new plugin and the new plugin object itself. The new plugin is placed
just after to the other plugin in the pipeline. If successful, it returns
a true value.

 my $success = $pipe->insert_after($name, $new_name, $new_plug);
 my $success = $pipe->insert_after($plug, $new_name, $new_plug);

=item C<bump_up>

Takes one or two arguments, the plugin or its alias, and the distance to bump
the plugin. The distance defaults to 1. The plugin will be moved the given
distance closer to the front of the pipeline. A warning is issued alerting you
if it would have been moved past the beginning of the pipeline, and the plugin
is placed at the beginning.  If successful, the new index of the plugin in
the pipeline is returned.

 my $pos = $pipe->bump_up($name);
 my $pos = $pipe->bump_up($plug);
 my $pos = $pipe->bump_up($name, $delta);
 my $pos = $pipe->bump_up($plug, $delta);

=item C<bump_down>

Takes one or two arguments, the plugin or its alias, and the distance to bump
the plugin. The distance defaults to 1. The plugin will be moved the given
distance closer to the end of the pipeline.  A warning is issued alerting you
if it would have been moved past the end of the pipeline, and the plugin is
placed at the end.If successful, the new index of the plugin in the pipeline
is returned.

 my $pos = $pipe->bump_down($name);
 my $pos = $pipe->bump_down($plug);
 my $pos = $pipe->bump_down($name, $delta);
 my $pos = $pipe->bump_down($plug, $delta);

=item C<remove>

Takes one argument, a plugin or its alias. The plugin is removed from the
pipeline.  This will yield an 'irc_plugin_del' event. If successful, it returns
plugin and its alias in list context or just the plugin in scalar context.

 my ($plug, $name) = $pipe->remove($the_name);
 my ($plug, $name) = $pipe->remove($the_plug);
 my $plug = $pipe->remove($the_name);
 my $plug = $pipe->remove($the_plug);

=item C<shift>

Takes no arguments. The first plugin in the pipeline is removed. This will
yield an 'irc_plugin_del' event. If successful, it returns the plugin and its
alias in list context or just the plugin in scalar context.

 my ($plug, $name) = $pipe->shift;
 my $plug = $pipe->shift;

=item C<pop>

Takes no arguments. The last plugin in the pipeline is removed. This will yield
an 'irc_plugin_del' event. If successful, it returns the plugin and its alias
in list context or just the plugin in scalar context.

 my ($plug, $name) = $pipe->pop;
 my $plug = $pipe->pop;

=item C<get>

Takes one argument, a plugin or its alias. If successful, it returns the
plugin and its alias in list context or just the plugin in scalar context.

 my ($plug, $name) = $pipe->get($the_name);
 my ($plug, $name) = $pipe->get($the_plug);
 my $plug = $pipe->get($the_name);
 my $plug = $pipe->get($the_plug);

=item C<get_index>

Takes one argument, a plugin or its alias. It returns the index
in the pipeline if successful, otherwise B<-1 will be returned, not undef>.

 my $pos = $pipe->get_index($name);
 my $pos = $pipe->get_index($plug);

=back

=head1 BUGS

None known so far.

=head1 SEE ALSO

L<POE::Component::IRC|POE::Component::IRC>, 

L<POE::Component::IRC::Plugin|POE::Component::IRC::Plugin>.  Also look at

L<POE::Session::MultiDispatch|POE::Session::MultiDispatch> which does something
similar for session events.

=head1 AUTHOR

Jeff C<japhy> Pinyan, <japhy@perlmonk.org>.

=cut
