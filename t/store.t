use strict;
use warnings;
use Test::More;
use Storable qw(dclone);
use lib '.';
use Koha::Plugin::Com::Library::MediaManager::Store;
{
    package FakeDB;
    sub new { bless {AutoCommit=>1,row=>$_[1],commits=>0},$_[0] }
    sub begin_work { $_[0]->{before}=Storable::dclone($_[0]->{row} || {}); $_[0]->{AutoCommit}=0; 1 }
    sub selectrow_hashref { $_[0]->{lock}=$_[1] =~ /FOR UPDATE/; $_[0]->{row} }
    sub do { $_[0]->{row}{consumed_at}=100 if $_[1] =~ /^UPDATE/; 1 }
    sub commit { $_[0]->{commits}++; $_[0]->{AutoCommit}=1; 1 }
    sub rollback { $_[0]->{row}=$_[0]->{before}; $_[0]->{AutoCommit}=1; 1 }
}
my %row=(issuer=>'library',audience=>'media-manager',client_id=>'dam',expires_at=>200,now_epoch=>100);
my %binding=(issuer=>'library',audience=>'media-manager',client_id=>'dam');
my $db=FakeDB->new({%row});
my $store=Koha::Plugin::Com::Library::MediaManager::Store->new($db,'mm_codes');
my ($status,$context)=$store->consume('a' x 64,\%binding,sub{{identity=>'staff'}},sub{});
is($status,'success','valid code accepted');
ok($db->{lock},'row locked during consumption');
is($db->{commits},1,'transaction committed');
($status)=$store->consume('a' x 64,\%binding,sub{die 'must not reauthorize replay'},sub{});
is($status,'replay','consumed code rejected');
for my $case ([{ %row,expires_at=>100 },'expired'],[undef,'invalid_grant'],
    [{%row,issuer=>'another'},'invalid_grant'],[{%row,client_id=>'another'},'invalid_grant']) {
    my $testdb=FakeDB->new($case->[0]);
    my $s=Koha::Plugin::Com::Library::MediaManager::Store->new($testdb,'mm_codes');
    ($status)=$s->consume('a' x 64,\%binding,sub{die 'must not authorize invalid grant'},sub{});
    is($status,$case->[1],$case->[1].' grant');
}
$db=FakeDB->new({%row});
$store=Koha::Plugin::Com::Library::MediaManager::Store->new($db,'mm_codes');
($status)=$store->consume('a' x 64,\%binding,sub{undef},sub{});
is($status,'permission_denied','authorization revoked');
ok($db->{row}{consumed_at},'revoked grant cannot later become valid');
$db=FakeDB->new({%row});
$store=Koha::Plugin::Com::Library::MediaManager::Store->new($db,'mm_codes');
eval { $store->consume('a' x 64,\%binding,sub{{ok=>1}},sub{die 'audit failure'}); };
like($@,qr/transaction failed/,'audit failure denies response');
ok(!defined($db->{row}{consumed_at}),'audit failure rolls back consumption');
done_testing;
