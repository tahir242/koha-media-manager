use strict;
use warnings;
use Test::More;
use lib '.', 't/lib';
use MockKoha;
use Koha::Plugin::Com::Library::MediaManager;
{
    package SchemaDB;
    sub do { push @{$_[0]->{sql}},$_[1]; 1 }
}
my $p=Koha::Plugin::Com::Library::MediaManager->new({});
$p->{data}={mam_url=>'https://existing.example.org',shared_secret=>'legacy',
    allowed_permissions=>'tools',button_label=>'Existing label'};
local $C4::Context::dbh=bless {sql=>[]},'SchemaDB';
ok($p->upgrade,'upgrade succeeds');
is($p->retrieve_data('shared_secret'),'legacy','legacy config retained for rollback');
is($p->retrieve_data('allowed_permissions'),'tools','legacy permission setting retained');
is($p->retrieve_data('button_label'),'Existing label','existing toolbar label retained');
ok(!$p->retrieve_data('client_secret_hash'),'legacy secret never promoted');
ok(!$p->_ready,'upgrade requires explicit v2 configuration');
ok($p->install,'repeated installation succeeds');
my $ddl=join "\n",@{$C4::Context::dbh->{sql}};
unlike($ddl,qr/DROP|TRUNCATE|DELETE/,'upgrade preserves audit records');
like($ddl,qr/PRIMARY KEY \(bucket,window_id\)/,'rate window key is composite');
ok($p->uninstall,'uninstall');
unlike(join("\n",@{$C4::Context::dbh->{sql}}),qr/DROP TABLE IF EXISTS mm_log/,'uninstall retains audit history');
done_testing;
