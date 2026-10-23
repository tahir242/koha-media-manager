package Koha::Plugin::Com::Library::MediaManager::Store;
use strict;
use warnings;
use Digest::SHA qw(sha256_hex);

sub new {
    my ($class, $dbh, $table) = @_;
    die 'Invalid table name' unless $table =~ /\A[a-z0-9_]+\z/;
    return bless { dbh=>$dbh, table=>$table }, $class;
}

sub issue {
    my ($self, $code, $row) = @_;
    my $t = $self->{table};
    $self->{dbh}->do(
        "INSERT INTO $t (code_hash,patron_id,biblio_id,branch,issuer,audience,client_id,issued_at,expires_at,correlation_id,browser_state) VALUES (?,?,?,?,?,?,?,UNIX_TIMESTAMP(),UNIX_TIMESTAMP()+?,?,?)",
        undef, sha256_hex($code), @$row{qw(patron_id biblio_id branch issuer audience client_id ttl correlation_id browser_state)}
    ) or die 'Authorization storage unavailable';
}

sub consume {
    my ($self, $code, $binding, $authorize, $audit) = @_;
    my $dbh = $self->{dbh};
    my $t = $self->{table};
    die 'Exchange requires an independent transaction' unless $dbh->{AutoCommit};
    my ($status,$result);
    eval {
        $dbh->begin_work or die 'Cannot start transaction';
        # The primary-key lock serializes all workers consuming this code.
        my $row = $dbh->selectrow_hashref(
            "SELECT *, UNIX_TIMESTAMP() AS now_epoch FROM $t WHERE code_hash=? FOR UPDATE",
            undef, sha256_hex($code));
        if (!$row) { $status = 'invalid_grant'; }
        elsif ($row->{issuer} ne $binding->{issuer} || $row->{audience} ne $binding->{audience}
            || $row->{client_id} ne $binding->{client_id}) { $status = 'invalid_grant'; }
        elsif (defined $row->{consumed_at}) { $status = 'replay'; }
        elsif ($row->{expires_at} <= $row->{now_epoch}) { $status = 'expired'; }
        else {
            # Revalidation is deliberately inside the transaction and before consumption.
            $result = $authorize->($row);
            $status = $result ? 'success' : 'permission_denied';
            $dbh->do("UPDATE $t SET consumed_at=UNIX_TIMESTAMP() WHERE code_hash=? AND consumed_at IS NULL",
                undef, sha256_hex($code)) or die 'Cannot consume authorization';
        }
        # A successful identity response is never returned unless audit + consume commit.
        $audit->($status, $row);
        $dbh->commit or die 'Cannot commit authorization';
        1;
    } or do {
        my $error = $@;
        eval { $dbh->rollback unless $dbh->{AutoCommit} };
        die 'Authorization transaction failed';
    };
    return ($status, $result);
}
1;
