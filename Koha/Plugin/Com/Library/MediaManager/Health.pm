package Koha::Plugin::Com::Library::MediaManager::Health;
use strict;
use warnings;
use Socket qw(AF_INET SOCK_STREAM getaddrinfo getnameinfo NI_NUMERICHOST);
use JSON::PP qw(decode_json);

sub check {
    my ($class, $config) = @_;
    my @allowed = split /,/, ($config->{health_ips} // '');
    return { reachable=>0, compatible=>0, message=>'Network tests disabled: no destination IPs approved.' } unless @allowed;
    my ($scheme,$host,$port,$base) = $config->{mam_url} =~ m{\A(https?)://([^/:]+)(?::([0-9]+))?(.*)\z};
    return { reachable=>0, compatible=>0, message=>'Application URL is not configured.' } unless $host;
    my $plain = $scheme eq 'http';
    return { reachable=>0, compatible=>0, message=>'Plain HTTP requires the test-only HTTP mode.' }
        if $plain && !$config->{insecure_http};
    $port ||= $plain ? 80 : 443;
    my %allowed = map { $_=>1 } @allowed;
    my ($error,@addresses) = getaddrinfo($host,$port,{ family=>AF_INET, socktype=>SOCK_STREAM });
    return { reachable=>0,compatible=>0,message=>'DNS lookup failed.' } if $error || !@addresses;
    my @ips;
    for my $address (@addresses) {
        my ($err,$ip) = getnameinfo($address->{addr}, NI_NUMERICHOST);
        return {reachable=>0,compatible=>0,message=>'DNS destination is not approved.'} if $err || !$allowed{$ip};
        push @ips,$ip;
    }
    my $result;
    eval {
        local $SIG{ALRM} = sub { die 'Timeout' };
        alarm 8;
        # Connect to the approved numeric address, never resolve again. Verify original hostname.
        my $socket;
        if ($plain) {
            require IO::Socket::INET;
            $socket = IO::Socket::INET->new(PeerAddr=>$ips[0], PeerPort=>$port, Proto=>'tcp', Timeout=>5)
                or die 'Connection failed';
        } else {
            require IO::Socket::SSL;
            $socket = IO::Socket::SSL->new(
                PeerAddr=>$ips[0], PeerPort=>$port, Timeout=>5,
                SSL_verify_mode=>1, SSL_hostname=>$host, SSL_verifycn_name=>$host,
                SSL_verifycn_scheme=>'http',
            ) or die 'TLS connection failed';
        }
        my $authority = $host . ($port == ($plain ? 80 : 443) ? '' : ":$port");
        print {$socket} "GET $base/.well-known/koha-media-manager HTTP/1.0\r\nHost: $authority\r\nAccept: application/json\r\nConnection: close\r\n\r\n" or die 'Write failed';
        my $response = '';
        while (length($response) < 16384) {
            my $n = sysread($socket, my $chunk, 2048);
            die 'Read failed' unless defined $n;
            last unless $n;
            $response .= $chunk;
        }
        close $socket;
        alarm 0;
        my ($headers,$body) = split /\r\n\r\n/,$response,2;
        my ($status) = ($headers // '') =~ /\AHTTP\/1\.[01] ([0-9]{3}) /;
        die 'Invalid response' unless $status;
        my $json = eval { decode_json($body // '') };
        my $compatible = $status == 200 && ref($json) eq 'HASH'
            && ($json->{protocol} // '') eq 'code-v2'
            && ($json->{audience} // '') eq 'media-manager';
        $result = {reachable=>1,compatible=>$compatible ? 1:0,
            message=>"HTTP $status; " . ($compatible ? 'protocol advertised.' : 'protocol not confirmed.') . ' Authenticated integration not verified.'
                . ($plain ? ' WARNING: unencrypted test-only HTTP.' : '')};
        1;
    } or do { alarm 0; $result = {reachable=>0,compatible=>0,message=>'Connection or TLS validation failed.'}; };
    return $result;
}
1;
