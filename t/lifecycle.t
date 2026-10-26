use strict;
use warnings;
use Test::More;
use lib '.', 't/lib';
use MockKoha;
use Koha::Plugin::Com::Library::MediaManager;
{
    package SchemaDB;
    sub do { push @{$_[0]->{sql}},$_[1]; 1 }
    # Columns already present (by table.column) on the simulated database.
    sub selectrow_array {
        my ($s,$sql,undef,$t,$c)=@_;
        return $s->{nullable}{"$t.$c"} ? 'YES' : 'NO' if $sql=~/IS_NULLABLE/;
        return $s->{columns}{"$t.$c"} ? 1 : 0;
    }
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
like($ddl,qr/ALTER TABLE mm_requests ADD COLUMN item_id INT NULL/,'upgrade adds item context to initiations');
like($ddl,qr/ALTER TABLE mm_codes ADD COLUMN item_id INT NULL/,'upgrade adds item context to codes');
like($ddl,qr/ALTER TABLE mm_log ADD COLUMN itemnumber INT/,'upgrade adds item to audit log');
like($ddl,qr/ALTER TABLE mm_requests MODIFY COLUMN biblio_id INT NULL/,'upgrade lets initiations carry no record');
like($ddl,qr/ALTER TABLE mm_codes MODIFY COLUMN biblio_id INT NULL/,'upgrade lets codes carry no record');
is($p->retrieve_data('schema_version'),'4','schema version 4 recorded');
{
    local $C4::Context::dbh=bless {sql=>[],columns=>{map { $_=>1 } qw(mm_requests.item_id mm_codes.item_id mm_log.itemnumber)},
        nullable=>{map { $_=>1 } qw(mm_requests.biblio_id mm_codes.biblio_id)}},'SchemaDB';
    ok($p->upgrade,'upgrade on schema 4 succeeds');
    unlike(join("\n",@{$C4::Context::dbh->{sql}}),qr/ALTER TABLE/,'existing columns are not added or changed again');
}
ok($p->uninstall,'uninstall');
unlike(join("\n",@{$C4::Context::dbh->{sql}}),qr/DROP TABLE IF EXISTS mm_log/,'uninstall retains audit history');
done_testing;
