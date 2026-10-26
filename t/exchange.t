use strict;
use warnings;
use Test::More;
use lib '.', 't/lib';
use MockKoha;
use Koha::Plugin::Com::Library::MediaManager;
use Koha::Plugin::Com::Library::MediaManager::Security qw(secret_hash);
{
    package ExchangeDB;
    sub selectrow_array { 1000 }
    package Grant;
    our $status='success';
    our $item_id;
    our $biblio_id=123;
    sub consume {
        my ($s,$code,$binding,$authorize,$audit)=@_;
        my $row={patron_id=>7,biblio_id=>$biblio_id,item_id=>$item_id,branch=>'MAIN',issuer=>'library',
            audience=>'media-manager',client_id=>'dam',issued_at=>990,expires_at=>1050,correlation_id=>'correlation'};
        my $response=$status eq 'success' ? $authorize->($row) : undef;
        my $result=($status eq 'success' && !$response) ? 'permission_denied' : $status;
        $audit->($result,$row);
        return ($result,$response);
    }
    package ExchangePlugin;
    our @ISA=('Koha::Plugin::Com::Library::MediaManager');
    our @events;
    our $rate=1;
    sub _db { bless {},'ExchangeDB' }
    sub _store { bless {},'Grant' }
    sub _rate { $rate }
    sub _audit { push @events, [@_[1..$#_]]; }
}
my $p=ExchangePlugin->new({});
$p->{data}={mam_url=>'https://dam.example.org',instance_id=>'library',client_id=>'dam',
    code_ttl=>60,rotation_grace=>300,audit_retention=>90,button_label=>'Upload',
    staff_policy=>'cataloguers',health_ips=>'',protocol=>'code-v2',client_secret_hash=>secret_hash('a' x 64)};
my $request={code=>'c' x 64};
my ($status,$body)=$p->exchange($request,'dam','a' x 64,'192.0.2.1');
is($status,200,'valid client and grant');
is($body->{context}{biblio_id},123,'context derived only from stored authorization');
is($body->{identity}{patron_id},7,'identity resolved from Koha');
ok(!exists $body->{identity}{name},'unnecessary personal data absent');
ok(exists $body->{context}{item_id} && !defined $body->{context}{item_id},'record-level grant has a null item');
like(JSON::PP::encode_json($body->{context}),qr/"item_id":null/,'null item serialized as JSON null');
{
    local $Grant::item_id=456;
    ($status,$body)=$p->exchange($request,'dam','a' x 64,'192.0.2.1');
    is($status,200,'item-level grant');
    is($body->{context}{item_id},456,'item derived only from stored authorization');
    like(JSON::PP::encode_json($body->{context}),qr/"item_id":456\b/,'item serialized as a number');
    local $Koha::Items::items{456};
    delete $Koha::Items::items{456};
    ($status)=$p->exchange($request,'dam','a' x 64,'192.0.2.1');
    is($status,403,'item deletion revalidated at exchange');
}
{
    local $Grant::item_id=456;
    local $Koha::Items::items{456}=999;
    ($status)=$p->exchange($request,'dam','a' x 64,'192.0.2.1');
    is($status,403,'item moved to another record revalidated at exchange');
}
{
    local $Grant::biblio_id;
    ($status,$body)=$p->exchange($request,'dam','a' x 64,'192.0.2.1');
    is($status,200,'dashboard grant without a record');
    like(JSON::PP::encode_json($body->{context}),qr/"biblio_id":null/,'dashboard grant has a null record');
    ok(!defined $body->{context}{item_id},'dashboard grant has no item');
    local $Grant::item_id=456;
    ($status)=$p->exchange($request,'dam','a' x 64,'192.0.2.1');
    is($status,403,'an item without its record is rejected');
}
{
    ($status,$body)=$p->exchange({%$request,item_id=>456},'dam','a' x 64,'192.0.2.1');
    is($status,400,'item cannot be supplied by the consumer');
}
for my $case (
    [$request,undef,undef,401,'missing client'],
    [$request,'dam','wrong',401,'invalid client'],
    [{},'dam','a' x 64,400,'missing code'],
    [{code=>'bad'},'dam','a' x 64,400,'invalid code'],
    [{%$request,biblio_id=>999},'dam','a' x 64,400,'altered bibliographic context'],
) {
    ($status,$body)=$p->exchange(@$case[0..2],'192.0.2.1');
    is($status,$case->[3],$case->[4]);
    ok($body->{error},'consistent error object');
}
{
    local $p->{data}{previous_secret_hash}=secret_hash('b' x 64);
    local $p->{data}{previous_secret_until}=1001;
    ($status)=$p->exchange($request,'dam','b' x 64,'192.0.2.1');
    is($status,200,'previous secret allowed during overlap');
    $p->{data}{previous_secret_until}=1000;
    ($status)=$p->exchange($request,'dam','b' x 64,'192.0.2.1');
    is($status,401,'previous secret expires at boundary');
}
for my $result (qw(replay expired invalid_grant)) {
    local $Grant::status=$result;
    ($status,$body)=$p->exchange($request,'dam','a' x 64,'192.0.2.1');
    is($status,400,"$result rejected");
    is($body->{error},'invalid_grant','grant failures indistinguishable to consumer');
}
{
    local $Koha::Patrons::patron->{locked}=1;
    ($status)=$p->exchange($request,'dam','a' x 64,'192.0.2.1');
    is($status,403,'account lock revalidated at exchange');
}
{
    local $Koha::Biblios::exists=0;
    ($status)=$p->exchange($request,'dam','a' x 64,'192.0.2.1');
    is($status,403,'record deletion revalidated at exchange');
}
{
    local $C4::Auth::permissions{edit_catalogue}=0;
    ($status)=$p->exchange($request,'dam','a' x 64,'192.0.2.1');
    is($status,403,'permission revocation revalidated at exchange');
}
{
    local $ExchangePlugin::rate=0;
    ($status)=$p->exchange($request,'dam','a' x 64,'192.0.2.1');
    is($status,429,'rate limit enforced');
}
my $logged=JSON::PP::encode_json(\@ExchangePlugin::events);
unlike($logged,qr/@{['a' x 64]}|@{['c' x 64]}/,'no secret or authorization code in audit data');
like($logged,qr/sso_replay_rejected/,'replay audit event');
done_testing;
