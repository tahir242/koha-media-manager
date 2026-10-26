package Koha::Plugin::Com::Library::MediaManager::Security;

# Copyright 2026 Tahir Ali Channa
#
# This file is part of Media Asset Management (MAM) for Koha.
#
# It is free software; you can redistribute it and/or modify it under the terms of the GNU General
# Public License as published by the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
# License for more details.
#
# You should have received a copy of the GNU General Public License along with it; if not, see
# <https://www.gnu.org/licenses>.

use strict;
use warnings;
use Digest::SHA qw(sha256_hex);
use JSON::PP ();
use Exporter 'import';
our @EXPORT_OK = qw(valid_id validate_config random_hex secret_hash secret_matches html_escape insecure_http_enabled);

# TEST-ONLY transport relaxation. Enabled exclusively by the server operator in the
# instance's koha-conf.xml (<media_manager_insecure_http>1</media_manager_insecure_http>
# inside <config>); never from plugin_data or the web interface. Off when absent.
sub insecure_http_enabled {
    my $value = eval { require C4::Context; C4::Context->config('media_manager_insecure_http') };
    return defined($value) && !ref($value) && $value =~ /\A\s*(?:1|yes|true|on)\s*\z/i ? 1 : 0;
}

sub valid_id {
    return defined $_[0] && !ref($_[0]) && $_[0] =~ /\A[1-9][0-9]{0,9}\z/
        && $_[0] <= 2147483647;
}

sub random_hex {
    # Bytes::Random::Secure is already a dependency of Koha::Token.
    # Koha::Token->generate uses String::Random on older releases: do not use it here.
    require Bytes::Random::Secure;
    my $rng = Bytes::Random::Secure->new( NonBlocking => 1 );
    return unpack 'H*', $rng->bytes(32);
}

sub secret_hash { return sha256_hex($_[0]); }

sub secret_matches {
    my ($secret, $hash) = @_;
    return 0 unless defined($secret) && !ref($secret) && length($secret) <= 256
        && defined($hash) && $hash =~ /\A[0-9a-f]{64}\z/;
    my $candidate = secret_hash($secret);
    my $difference = 0;
    $difference |= ord(substr($candidate, $_, 1)) ^ ord(substr($hash, $_, 1)) for 0 .. 63;
    return $difference == 0;
}

sub html_escape {
    my $s = $_[0] // '';
    $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g; $s =~ s/'/&#39;/g;
    return $s;
}

sub validate_config {
    my ($input, $options) = @_;
    my %c = %$input;
    my @errors;
    my $url = $c{mam_url} // '';
    $url =~ s{/+\z}{};
    # Deliberately narrow grammar: HTTPS DNS name, optional port, simple base path.
    # No credentials, query, fragment, escapes, backslashes or ambiguous authorities.
    # http:// is accepted only when the operator enabled the test-only HTTP mode.
    my $scheme = ($options && $options->{allow_http}) ? 'https?' : 'https';
    if ($url !~ m{\A$scheme://([a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?)(?::([0-9]{1,5}))?((?:/[a-zA-Z0-9_-]+)*)\z}
        || $url =~ m{https?://[^/]*\.\.} || (defined($2) && ($2 < 1 || $2 > 65535))) {
        push @errors, $scheme eq 'https'
            ? 'Application URL must be HTTPS with a DNS hostname and a simple optional base path.'
            : 'Application URL must be HTTP(S) with a hostname and a simple optional base path.';
    }
    $c{mam_url} = $url;
    for my $key (qw(instance_id client_id)) {
        push @errors, "$key must contain 1-64 letters, digits, dots, underscores or hyphens."
            unless ($c{$key} // '') =~ /\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}\z/;
    }
    for my $spec ([code_ttl=>30=>120], [rotation_grace=>120=>3600], [audit_retention=>1=>3650]) {
        my ($key,$min,$max) = @$spec;
        push @errors, "$key must be an integer between $min and $max."
            unless defined($c{$key}) && $c{$key} =~ /\A[0-9]{1,4}\z/
                && $c{$key} >= $min && $c{$key} <= $max;
    }
    push @errors, 'Button label must contain 1-80 printable characters.'
        unless length($c{button_label} // '') >= 1 && length($c{button_label}) <= 80
            && $c{button_label} !~ /[\x00-\x1f\x7f]/;
    push @errors, 'Choose cataloguers or superlibrarians for the staff policy.'
        unless ($c{staff_policy} // '') =~ /\A(?:cataloguers|superlibrarians)\z/;
    my @ips = split /\s*,\s*/, ($c{health_ips} // '');
    for my $ip (@ips) {
        my @parts = split /\./, $ip, -1;
        push @errors, 'Health destinations must be comma-separated canonical IPv4 addresses.'
            unless @parts == 4 && !grep { !/\A(?:0|[1-9][0-9]{0,2})\z/ || $_ > 255 } @parts;
        push @errors, 'Unspecified, loopback, link-local and multicast health destinations are forbidden.'
            if @parts == 4 && ($parts[0] == 0 || $parts[0] == 127 || $parts[0] >= 224
                || ($parts[0] == 169 && $parts[1] == 254));
    }
    $c{health_ips} = join ',', @ips;
    $c{protocol} = 'code-v2';
    return (\%c, \@errors);
}
1;
