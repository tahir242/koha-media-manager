#!/usr/bin/perl
use strict;
use warnings;
use Koha::Plugin::Com::Library::MediaManager;
# Run as the Koha instance user with KOHA_CONF and PERL5LIB set by koha-shell.
die "Usage: maintenance.pl --run\n" unless @ARGV == 1 && $ARGV[0] eq '--run';
my $plugin = Koha::Plugin::Com::Library::MediaManager->new;
die "Plugin unavailable\n" unless $plugin;
$plugin->maintenance;
print "Media Manager maintenance completed\n";
