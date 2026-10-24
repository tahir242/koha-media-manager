use strict;
use warnings;
use Test::More;
use lib '.';
use Koha::Plugin::Com::Library::MediaManager::Security qw(valid_id validate_config secret_hash secret_matches html_escape);
my %good = (mam_url=>'https://dam.example.org/base/',instance_id=>'library',client_id=>'dam',
    code_ttl=>60,rotation_grace=>300,audit_retention=>90,button_label=>'Attach Media',
    staff_policy=>'cataloguers',health_ips=>'10.0.0.5,192.168.1.20');
my ($cfg,$err)=validate_config(\%good);
is_deeply($err,[],'valid configuration');
is($cfg->{mam_url},'https://dam.example.org/base','normalize URL');
for my $bad ('http://host','javascript:alert(1)','https://user:pass@host','https://host?next=evil',
    'https://host/#fragment','https://host\@evil','https://host/%2f%2fevil',"https://host\r\nHeader: x",
    'https://host:99999','https://host/../evil') {
    my (undef,$errors)=validate_config({%good,mam_url=>$bad});
    ok(@$errors,"reject unsafe URL $bad");
}
for my $bad (0,-1,'1e3','12x','01',2147483648,"1\n",undef) { ok(!valid_id($bad),'reject invalid biblio ID'); }
ok(valid_id(123),'valid positive ID');
for my $case ([code_ttl=>0],[code_ttl=>121],[staff_policy=>'tools'],[instance_id=>'a/b'],
    [button_label=>"bad\nlabel"],[health_ips=>'127.0.0.1'],[health_ips=>'169.254.169.254'],
    [health_ips=>'010.0.0.1'],[health_ips=>'999.1.1.1']) {
    my (undef,$errors)=validate_config({%good,$case->[0]=>$case->[1]});
    ok(@$errors,'reject invalid '.$case->[0]);
}
my $secret='a' x 64;
ok(secret_matches($secret,secret_hash($secret)),'matching secret');
ok(!secret_matches('b' x 64,secret_hash($secret)),'wrong secret');
ok(!secret_matches(undef,secret_hash($secret)),'missing secret');
is(html_escape(q{<script>"'&}), '&lt;script&gt;&quot;&#39;&amp;','HTML context escaping');
done_testing;
