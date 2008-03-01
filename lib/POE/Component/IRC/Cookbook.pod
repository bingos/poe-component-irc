package POE::Component::IRC::Cookbook;

use strict;
use warnings;

1;
__END__

=head1 NAME

POE::Component::IRC::Cookbook - The PoCo-IRC Cookbook: Overview

=head1 DESCRIPTION

B<Note:> This is a work in progress.

L<POE::Component::IRC|POE::Component::IRC> is a fully event-driven IRC client
module built around L<POE|POE>. It can be used to write IRC client applications
of any kind. This cookbook features working examples of programs demonstrating
the capabilities of POE::Component::IRC.

=head1 RECIPES

=head2 GENERAL

=over

=item L<Disconnecting|POE::Component::IRC::Cookbook::Disconnecting>

Shows you how to disconnect gracefully.

=back

=head2 BOTS

=over

=item L<A basic bot|POE::Component::IRC::Cookbook::BasicBot>

A basic bot demonstrating the basics of PoCo-IRC.

=item L<Translator|POE::Component::IRC::Cookbook::Translator>

Add translating capabilities to your bot.

=item L<Resolver|POE::Component::IRC::Cookbook::Resolver>

Have your bot resolve DNS records for you.

=item L<Seen|POE::Component::IRC::Cookbook::Seen>

Implement the "seen" feature found in many bots, which tells you when your bot
last saw a particular user, and what they were doing/saying.

=item L<MegaHal|POE::Component::IRC::Cookbook::MegaHal>

Allow your bot to talk, using artificial "intelligence".

=item L<Feeds|POE::Component::IRC::Cookbook::Feeds>

Use your bot as an RSS/Atom feed aggregator.

=item L<Reminder|POE::Component::IRC::Cookbook::Reminder>

Have your bot remind you about something at a later time.

=item L<Messenger|POE::Component::IRC::Cookbook::Messenger>

Have your bot deliver messages to users as soon as they become active.

=item L<Eval|POE::Component::IRC::Cookbook::Eval>

Have your bot evaluate mathematical expressions and code.

=item L<Reload|POE::Component::IRC::Cookbook::Reload>

Structure your code in such a way that your bot can be reprogrammed at runtime
without reconnecting to the IRC server.

=back

=head2 CLIENTS

=over

=item L<Gtk2|POE::Component::IRC::Cookbook::Gtk2Client>

A simple IRC client with a Gtk2 interface.

=item L<ReadLine|POE::Component::IRC::Cookbook::ReadLineClient>

A simple IRC client with a ReadLine interface.

=back

=head1 AUTHOR

Hinrik E<Ouml>rn SigurE<eth>sson, hinrik.sig@gmail.com
