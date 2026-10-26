use strict;
use warnings;
use Test::More;
use lib '.', 't/lib';
use MockKoha;
use Koha::Plugin::Com::Library::MediaManager;
use Koha::Plugin::Com::Library::MediaManager::Security qw(secret_hash);
{
    package AuthorizeDB;
    our @inserts;
    sub do { my ($s,$sql,undef,@bind)=@_; push @inserts,\@bind if $sql=~/INTO mm_requests/; 1 }
    package AuthorizePlugin;
    our @ISA=('Koha::Plugin::Com::Library::MediaManager');
    sub _db { bless {},'AuthorizeDB' }
    sub _rate { 1 }
    sub _audit { 1 }
    sub _error { $_[0]->{error}=$_[3]; return; }
}
my $p=AuthorizePlugin->new({});
$p->{data}={mam_url=>'https://dam.example.org',instance_id=>'library',client_id=>'dam',
    code_ttl=>60,rotation_grace=>300,audit_retention=>90,button_label=>'Upload',staff_policy=>'cataloguers',
    health_ips=>'',protocol=>'code-v2',client_secret_hash=>secret_hash('a' x 64)};
local $ENV{HTTPS}='on';
sub run_authorize {
    my (%params)=@_;
    local %CGI::params=(biblionumber=>123,%params);
    @AuthorizeDB::inserts=(); delete $p->{error};
    my $output='';
    open my $fh,'>',\$output or die $!;
    { local *STDOUT=$fh; $p->_authorize(CGI->new); }
    return $output;
}
like(run_authorize(),qr{/sso/koha/start\?request=},'record-level initiation');
ok(!defined $AuthorizeDB::inserts[0][4],'record-level initiation stores no item');
like(run_authorize(itemnumber=>''),qr{/sso/koha/start},'empty itemnumber is record-level');
ok(!defined $AuthorizeDB::inserts[0][4],'empty itemnumber stores no item');
like(run_authorize(itemnumber=>456),qr{/sso/koha/start\?request=},'item-level initiation');
is($AuthorizeDB::inserts[0][3],123,'record stored');
is($AuthorizeDB::inserts[0][4],456,'item stored with its record');
for my $case ([0,400,'zero'],['45x',400,'non-numeric'],[457,404,'deleted item']) {
    is(run_authorize(itemnumber=>$case->[0]),'',"no redirect for $case->[2]");
    is($p->{error},$case->[1],"$case->[2] rejected");
    ok(!@AuthorizeDB::inserts,"no initiation stored for $case->[2]");
}
{
    like(run_authorize(scope=>'dashboard',biblionumber=>undef),qr{/sso/koha/start\?request=},'dashboard initiation without a record');
    ok(!defined $AuthorizeDB::inserts[0][3],'dashboard initiation stores no record');
    ok(!defined $AuthorizeDB::inserts[0][4],'dashboard initiation stores no item');
    run_authorize(scope=>'dashboard',itemnumber=>456);
    ok(!defined $AuthorizeDB::inserts[0][3] && !defined $AuthorizeDB::inserts[0][4],'dashboard initiation ignores record and item parameters');
    is(run_authorize(scope=>'other',biblionumber=>undef),'','unknown scope still needs a record');
    is($p->{error},400,'missing record rejected');
}
{
    local $Koha::Items::items{456}=999;
    is(run_authorize(itemnumber=>456),'','no redirect for an item of another record');
    is($p->{error},404,'item of another record rejected');
}
done_testing;
