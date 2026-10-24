use strict;
use warnings;
use Test::More;
use lib '.';
use Koha::Plugin::Com::Library::MediaManager::Store;
BEGIN {
    plan skip_all=>'Set MM_TEST_DSN for a disposable mediamanager_test database'
        unless ($ENV{MM_TEST_DSN} // '') =~ /\Adbi:(?:mysql|MariaDB):database=mediamanager_test(?:;|\z)/;
    plan skip_all=>'Real DBI and MariaDB/MySQL driver required' unless eval { require DBI; 1 };
    plan skip_all=>'Run fork concurrency tests on Linux' if $^O eq 'MSWin32' || $^O eq 'msys';
}
sub connect_db {
    DBI->connect($ENV{MM_TEST_DSN},$ENV{MM_TEST_USER},$ENV{MM_TEST_PASSWORD},
        {RaiseError=>1,PrintError=>0,AutoCommit=>1});
}
my $table='mm_test_codes_'.$$;
my $dbh=connect_db();
$dbh->do("CREATE TABLE $table (
    code_hash CHAR(64) PRIMARY KEY,patron_id INT,biblio_id INT,branch VARCHAR(10),
    issuer VARCHAR(64),audience VARCHAR(64),client_id VARCHAR(64),issued_at BIGINT,
    expires_at BIGINT,consumed_at BIGINT NULL,correlation_id CHAR(64),browser_state VARCHAR(128)
) ENGINE=InnoDB");
END { if ($dbh && $table) { $dbh->do("DROP TABLE IF EXISTS $table"); $dbh->disconnect; } }
my $store=Koha::Plugin::Com::Library::MediaManager::Store->new($dbh,$table);
my $code='f' x 64;
$store->issue($code,{patron_id=>1,biblio_id=>2,branch=>'MAIN',issuer=>'test',audience=>'media-manager',
    client_id=>'dam',ttl=>60,correlation_id=>'test',browser_state=>'s' x 43});
pipe(my $reader,my $writer) or die $!;
my @children;
for (1..2) {
    my $pid=fork(); die 'fork failed' unless defined $pid;
    if (!$pid) {
        close $writer;
        $dbh->{InactiveDestroy}=1;
        undef $dbh; # Never reuse or disconnect a parent connection in a child.
        my $child=connect_db();
        sysread($reader,my $go,1);
        my $s=Koha::Plugin::Com::Library::MediaManager::Store->new($child,$table);
        my ($status)=$s->consume($code,{issuer=>'test',audience=>'media-manager',client_id=>'dam'},
            sub { select undef,undef,undef,0.2; return {ok=>1} },sub {});
        $child->disconnect;
        exit($status eq 'success' ? 10 : $status eq 'replay' ? 20 : 30);
    }
    push @children,$pid;
}
close $reader;
syswrite($writer,'go');
close $writer;
my @results;
for my $pid (@children) { waitpid($pid,0); push @results,$? >> 8; }
is_deeply([sort {$a<=>$b} @results],[10,20],'exactly one real database consumer succeeds');
my ($consumed)=$dbh->selectrow_array("SELECT consumed_at FROM $table");
ok($consumed,'consumption persisted');
done_testing;
