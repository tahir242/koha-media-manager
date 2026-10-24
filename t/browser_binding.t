use strict;
use warnings;
use Test::More;
use lib '.', 't/lib';
use MockKoha;
use Digest::SHA qw(sha256_hex);
use Koha::Plugin::Com::Library::MediaManager;
use Koha::Plugin::Com::Library::MediaManager::Security qw(secret_hash);
{
    package BindingDB;
    sub begin_work { $_[0]->{AutoCommit}=0; 1 }
    sub selectrow_hashref { $_[0]->{row} }
    sub do { 1 }
    sub commit { $_[0]->{AutoCommit}=1; 1 }
    sub rollback { $_[0]->{AutoCommit}=1; 1 }
    package IssuedGrant;
    our $issued;
    sub issue { $issued=$_[2]; 1 }
    package BindingPlugin;
    our @ISA=('Koha::Plugin::Com::Library::MediaManager');
    our $db;
    sub _db { $db }
    sub _store { bless {},'IssuedGrant' }
    sub _audit { 1 }
    sub _error { $_[0]->{error}=$_[3]; return; }
}
my $p=BindingPlugin->new({});
$p->{data}={mam_url=>'https://dam.example.org',instance_id=>'library',client_id=>'dam',
    code_ttl=>60,rotation_grace=>300,audit_retention=>90,button_label=>'Upload',staff_policy=>'cataloguers',
    health_ips=>'',protocol=>'code-v2',client_secret_hash=>secret_hash('a' x 64)};
my %row=(patron_id=>7,biblio_id=>123,branch=>'MAIN',binding=>Koha::Plugin::Com::Library::MediaManager::_binding($p->_config),
    session_hash=>sha256_hex('test-session'),expires_at=>200,now_epoch=>100,correlation_id=>'correlation');
local $ENV{HTTPS}='on';
local %CGI::params=(request=>'a' x 64,state=>'s' x 43);
sub run_complete {
    my ($row)=@_;
    $BindingPlugin::db=bless {AutoCommit=>1,row=>$row},'BindingDB';
    $IssuedGrant::issued=undef; delete $p->{error};
    my $output='';
    open my $fh,'>',\$output or die $!;
    { local *STDOUT=$fh; $p->_complete(CGI->new); }
    return $output;
}
my $url=run_complete({%row});
like($url,qr{\Ahttps://dam.example.org/sso/koha\?code=[a-f0-9]{64}&state=s{43}\z},'callback contains only code and state');
is($IssuedGrant::issued->{browser_state},'s' x 43,'state bound into stored grant');
is($IssuedGrant::issued->{biblio_id},123,'biblio derived from initiation record');
for my $case ([session_hash=>'other'],[patron_id=>8],[binding=>'different instance'],[expires_at=>100],[consumed_at=>99]) {
    my $output=run_complete({%row,$case->[0]=>$case->[1]});
    is($output,'','no redirect for invalid '.$case->[0]);
    ok(!$IssuedGrant::issued,'no code issued');
    is($p->{error},400,'safe rejection');
}
ok(!defined $IssuedGrant::issued->{item_id},'record-level initiation issues no item');
run_complete({%row,item_id=>456});
is($IssuedGrant::issued->{item_id},456,'item derived from initiation record');
{
    local $Koha::Items::items{456}=999;
    is(run_complete({%row,item_id=>456}),'','no redirect when the item moved to another record');
    ok(!$IssuedGrant::issued,'no code issued for a moved item');
}
{
    is(run_complete({%row,item_id=>457}),'','no redirect when the item was deleted');
    ok(!$IssuedGrant::issued,'no code issued for a deleted item');
}
{
    local $CGI::params{state}='bad';
    run_complete({%row});
    ok(!$IssuedGrant::issued,'malformed state rejected');
}
done_testing;
