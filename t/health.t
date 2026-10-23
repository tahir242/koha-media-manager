use strict;
use warnings;
use Test::More;
use lib '.';
use Koha::Plugin::Com::Library::MediaManager::Health;
my $cfg={mam_url=>'https://dam.example.org',health_ips=>''};
my $r=Koha::Plugin::Com::Library::MediaManager::Health->check($cfg);
ok(!$r->{reachable},'no network request without approved destinations');
{
    no warnings qw(redefine once);
    local *Koha::Plugin::Com::Library::MediaManager::Health::getaddrinfo=sub { ('DNS failure') };
    $r=Koha::Plugin::Com::Library::MediaManager::Health->check({%$cfg,health_ips=>'10.0.0.5'});
    like($r->{message},qr/DNS lookup failed/,'DNS failure safely reported');
}
{
    no warnings qw(redefine once);
    local *Koha::Plugin::Com::Library::MediaManager::Health::getaddrinfo=sub { ('',{addr=>'fixture'}) };
    local *Koha::Plugin::Com::Library::MediaManager::Health::getnameinfo=sub { ('','169.254.169.254') };
    $r=Koha::Plugin::Com::Library::MediaManager::Health->check({%$cfg,health_ips=>'10.0.0.5'});
    like($r->{message},qr/not approved/,'DNS rebinding to metadata service blocked before connection');
}
{
    require IO::Socket::SSL;
    no warnings qw(redefine once);
    local *Koha::Plugin::Com::Library::MediaManager::Health::getaddrinfo=sub { ('',{addr=>'fixture'}) };
    local *Koha::Plugin::Com::Library::MediaManager::Health::getnameinfo=sub { ('','10.0.0.5') };
    local *IO::Socket::SSL::new=sub {
        my ($class,%args)=@_;
        is($args{PeerAddr},'10.0.0.5','connection uses pinned numeric address');
        is($args{SSL_verifycn_name},'dam.example.org','TLS verifies configured hostname');
        is($args{SSL_verify_mode},1,'certificate verification enabled');
        die 'sensitive transport error';
    };
    $r=Koha::Plugin::Com::Library::MediaManager::Health->check({%$cfg,health_ips=>'10.0.0.5'});
    ok(!$r->{reachable},'TLS failure rejected');
    unlike($r->{message},qr/sensitive/,'raw exceptions not exposed');
}
done_testing;
