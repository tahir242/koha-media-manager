package Koha::Plugin::Com::Library::MediaManager;
use Modern::Perl;
use base qw(Koha::Plugins::Base);
use C4::Context;
use C4::Auth qw(haspermission check_cookie_auth);
use CGI;
use Koha::Biblios;
use Koha::Patrons;
use Koha::Token;
use JSON::PP qw(encode_json decode_json);
use Digest::SHA qw(sha256_hex);
use POSIX qw(strftime);
use URI::Escape qw(uri_escape);
use Koha::Plugin::Com::Library::MediaManager::Security qw(valid_id validate_config random_hex secret_hash secret_matches html_escape insecure_http_enabled);
use Koha::Plugin::Com::Library::MediaManager::Store;
use Koha::Plugin::Com::Library::MediaManager::Health;

our $VERSION = '2.3.0';
our $metadata = {
    name=>'Media Asset Management (MAM)', author=>'Tahir Ali Channa',
    description=>'Adds an "Upload Secure Media" button to bibliographic records. One click signs staff in to the '
        .'SIUT Digital Asset Management application (no second password), where they upload, review and publish '
        .'digital files for that record.',
    date_authored=>'2026-10-21', date_updated=>'2026-10-24',
    minimum_version=>'22.1100000', maximum_version=>undef, version=>$VERSION,
};
my @settings = qw(mam_url instance_id client_id code_ttl rotation_grace button_label staff_policy health_ips audit_retention);

sub new {
    my ($class,$args) = @_;
    $args ||= {};
    $args->{metadata} = { %$metadata, class=>$class };
    return $class->SUPER::new($args);
}

sub _table { return $_[0]->get_qualified_table_name($_[1]); }
sub _db { return C4::Context->dbh; }

sub install { return $_[0]->_migrate; }
sub upgrade { return $_[0]->_migrate; }

sub _migrate {
    my ($self) = @_;
    my $dbh = $self->_db;
    my $log = $self->_table('log');
    # Keep the v1 audit schema and records intact. Structured details hold correlation IDs.
    $dbh->do(qq{CREATE TABLE IF NOT EXISTS $log (
        id INT AUTO_INCREMENT PRIMARY KEY, userid VARCHAR(75) NOT NULL,
        borrowernumber INT DEFAULT NULL, biblionumber INT DEFAULT NULL,
        action VARCHAR(50) NOT NULL DEFAULT 'unknown', ip_address VARCHAR(45),
        status VARCHAR(20) NOT NULL DEFAULT 'success', details TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_mm_created_at (created_at), INDEX idx_mm_userid (userid),
        INDEX idx_mm_biblionumber (biblionumber)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci}) or die 'Audit schema unavailable';
    my $codes = $self->_table('codes');
    $dbh->do(qq{CREATE TABLE IF NOT EXISTS $codes (
        code_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
        patron_id INT NOT NULL, biblio_id INT NOT NULL, branch VARCHAR(10) NOT NULL,
        issuer VARCHAR(64) NOT NULL, audience VARCHAR(64) NOT NULL, client_id VARCHAR(64) NOT NULL,
        issued_at BIGINT NOT NULL, expires_at BIGINT NOT NULL, consumed_at BIGINT NULL,
        correlation_id CHAR(64) NOT NULL, browser_state VARCHAR(128) NOT NULL, INDEX mm_expiry (expires_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin}) or die 'Code schema unavailable';
    my $requests = $self->_table('requests');
    $dbh->do(qq{CREATE TABLE IF NOT EXISTS $requests (
        request_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin PRIMARY KEY,
        session_hash CHAR(64) NOT NULL, patron_id INT NOT NULL, biblio_id INT NOT NULL,
        branch VARCHAR(10) NOT NULL, binding CHAR(64) NOT NULL, expires_at BIGINT NOT NULL,
        consumed_at BIGINT NULL, correlation_id CHAR(64) NOT NULL, INDEX mm_request_expiry (expires_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin}) or die 'Initiation schema unavailable';
    my $rates = $self->_table('rates');
    $dbh->do(qq{CREATE TABLE IF NOT EXISTS $rates (
        bucket CHAR(64) CHARACTER SET ascii NOT NULL, window_id BIGINT NOT NULL,
        attempts INT NOT NULL, PRIMARY KEY (bucket,window_id), INDEX mm_window (window_id)
    ) ENGINE=InnoDB}) or die 'Rate schema unavailable';
    return $self->_defaults;
}

sub _defaults {
    my ($self) = @_;
    my %defaults = (
        protocol=>'code-v2', code_ttl=>'60', rotation_grace=>'300',
        audit_retention=>'90', button_label=>'Upload Secure Media',
        staff_policy=>'cataloguers', health_ips=>'', schema_version=>'2',
    );
    for my $key (keys %defaults) {
        $self->store_data({$key=>$defaults{$key}}) unless defined $self->retrieve_data($key);
    }
    # Existing mam_url, shared_secret and allowed_permissions are preserved for rollback.
    # Legacy secrets are never promoted to v2 authentication credentials.
    return 1;
}

sub uninstall {
    my ($self) = @_;
    # Retain historical audits, invalidate pending grants and remove rate state.
    for my $name (qw(codes requests rates)) {
        my $table = $self->_table($name);
        $self->_db->do("DROP TABLE IF EXISTS $table") or die 'Uninstall failed';
    }
    return 1;
}

sub _config {
    my ($self) = @_;
    return { map { $_=>($self->retrieve_data($_) // '') } @settings };
}

sub _ready {
    my ($self) = @_;
    my (undef,$errors) = validate_config($self->_config,{allow_http=>$self->_insecure_http});
    return !@$errors && ($self->retrieve_data('protocol') // '') eq 'code-v2'
        && ($self->retrieve_data('client_secret_hash') // '') =~ /\A[0-9a-f]{64}\z/;
}

sub _patron {
    my ($self,$id) = @_;
    return unless valid_id($id);
    my $p = Koha::Patrons->find($id);
    return unless $p && $p->userid && !$p->account_locked && !$p->is_expired;
    return if $p->lost || $p->gonenoaddress || $p->is_debarred;
    return $p;
}

sub _capabilities {
    my ($self,$p) = @_;
    return [] unless $p && haspermission($p->userid,{catalogue=>1})
        && haspermission($p->userid,{plugins=>'tool'});
    return [qw(media.access media.upload media.manage media.admin)] if ($p->flags // 0) & 1;
    return [] unless ($self->retrieve_data('staff_policy') // '') eq 'cataloguers';
    return [] unless haspermission($p->userid,{editcatalogue=>'edit_catalogue'});
    return [qw(media.access media.upload)];
}

sub _staff {
    my ($self,$cgi) = @_;
    my $cookie = $cgi->cookie('CGISESSID') // '';
    return unless $cookie;
    my ($status,$session) = check_cookie_auth($cookie,{catalogue=>1});
    return unless $status eq 'ok' && $session;
    # An OPAC session must not be promoted into a staff authorization.
    return unless ($session->param('interface') // '') eq 'intranet';
    my $p = $self->_patron($session->param('number'));
    return unless $p;
    my $env = C4::Context->userenv;
    return unless $env && ($env->{number} // '') eq $p->borrowernumber;
    return ($p,$session);
}

sub _admin {
    my ($self,$cgi) = @_;
    my ($p) = $self->_staff($cgi);
    return $p && (($p->flags // 0) & 1);
}

sub _csrf {
    my ($self,$cgi) = @_;
    my $session_id = scalar $cgi->cookie('CGISESSID');
    die 'Staff session required for CSRF token' unless defined($session_id) && length($session_id);
    my $token = Koha::Token->new->generate_csrf({session_id=>$session_id});
    die 'Could not generate staff CSRF token' unless defined($token) && length($token);
    return $token;
}

sub _form_params {
    my ($self,$cgi) = @_;
    # Koha.GenerateCSRF reads sessionID from the Template Toolkit stash.
    # The plugin-specific fallback supports older Koha without that TT method.
    return (
        sessionID => scalar $cgi->cookie('CGISESSID'),
        mm_csrf_token => $self->_csrf($cgi),
        # Shown on the pages so administrators can confirm which code Koha is running.
        mm_version => $VERSION,
    );
}
sub _valid_post {
    my ($self,$cgi) = @_;
    return $cgi->request_method eq 'POST' && Koha::Token->new->check_csrf({
        session_id=>scalar $cgi->cookie('CGISESSID'), token=>scalar $cgi->param('csrf_token'),
    });
}
sub _https { return ($ENV{HTTPS} // '') =~ /\A(?:on|1)\z/i; }
# TEST-ONLY HTTP mode: enabled by a superlibrarian with the button on the Configure page
# (plugin_data insecure_http=1), or by the server operator in koha-conf.xml.
sub _insecure_http {
    my ($self) = @_;
    return (insecure_http_enabled() || ($self->retrieve_data('insecure_http') // '') eq '1') ? 1 : 0;
}
# HTTPS, or the TEST-ONLY HTTP mode (see docs/CONFIGURATION.md).
sub _transport_ok { my ($self) = @_; return _https() || $self->_insecure_http; }

sub _audit {
    my ($self,$action,$status,$context,$details) = @_;
    $context ||= {};
    my $table = $self->_table('log');
    my $safe = { correlation_id=>$context->{correlation_id} // random_hex(), %{ $details || {} } };
    $self->_db->do(
        "INSERT INTO $table (userid,borrowernumber,biblionumber,action,ip_address,status,details) VALUES (?,?,?,?,?,?,?)",
        undef, $context->{userid} // '', $context->{patron_id}, $context->{biblio_id},
        $action, substr($context->{source_ip} // $ENV{REMOTE_ADDR} // '',0,45), $status, encode_json($safe),
    ) or die 'Audit write failed';
}

sub _rate {
    my ($self,$key,$limit) = @_;
    my $t = $self->_table('rates');
    my $dbh = $self->_db;
    my ($window) = $dbh->selectrow_array('SELECT FLOOR(UNIX_TIMESTAMP()/60)');
    my $bucket = sha256_hex($key);
    $dbh->do("INSERT INTO $t (bucket,window_id,attempts) VALUES (?,?,1) ON DUPLICATE KEY UPDATE attempts=attempts+1",
        undef,$bucket,$window) or die 'Rate storage unavailable';
    my ($count) = $dbh->selectrow_array("SELECT attempts FROM $t WHERE bucket=? AND window_id=?",undef,$bucket,$window);
    return $count <= $limit;
}

sub configure {
    my ($self) = @_;
    my $cgi = $self->{cgi};
    return $self->_error('Access denied','Only superlibrarians may administer this integration.',403) unless $self->_admin($cgi);

    my $config = $self->_config;
    my $allow_http = $self->_insecure_http;
    my @errors;
    my $saved = 0;
    if ($cgi->request_method eq 'POST') {
        return $self->_error('Invalid request','CSRF validation failed.',403) unless $self->_valid_post($cgi);
        # "Allow HTTP (test networks only)" checkbox. Saving over plain HTTP requires it,
        # so running without HTTPS is always a conscious, audited choice.
        $allow_http = (scalar($cgi->param('insecure_http')) // '') eq '1' || insecure_http_enabled() ? 1 : 0;
        my %input = map { $_=>scalar($cgi->param($_)) // '' } @settings;
        my ($clean,$validation) = validate_config(\%input,{allow_http=>$allow_http});
        @errors = @$validation;
        push @errors,'Koha is opened over plain HTTP: tick "Allow HTTP" (test networks only) or use HTTPS.'
            unless _https() || $allow_http;
        my $secret = scalar($cgi->param('client_secret')) // '';
        push @errors,'Replacement secret must be 64 lowercase hexadecimal characters generated from 32 random bytes.'
            if length($secret) && $secret !~ /\A[0-9a-f]{64}\z/;
        push @errors,'A new client secret is required for first configuration.'
            unless length($secret) || $self->retrieve_data('client_secret_hash');
        if (!@errors) {
            my $dbh = $self->_db;
            eval {
                $dbh->begin_work or die 'Transaction unavailable';
                # Serialize administrator saves and rotations on a stable plugin_data row.
                $dbh->selectrow_array('SELECT plugin_value FROM plugin_data WHERE plugin_class=? AND plugin_key=? FOR UPDATE',
                    undef,ref($self),'schema_version');
                if (length($secret)) {
                    my ($now) = $dbh->selectrow_array('SELECT UNIX_TIMESTAMP()');
                    $self->store_data({
                        previous_secret_hash=>$self->retrieve_data('client_secret_hash') // '',
                        previous_secret_until=>$now+$clean->{rotation_grace},
                        client_secret_hash=>secret_hash($secret),
                    });
                }
                my $was_http = ($self->retrieve_data('insecure_http') // '') eq '1' ? 1 : 0;
                $self->store_data({%$clean, insecure_http=>$allow_http ? '1' : '0'});
                my ($p) = $self->_staff($cgi);
                my $who = {userid=>$p->userid,patron_id=>$p->borrowernumber};
                $self->_audit('configuration_updated','success',$who,{});
                $self->_audit($allow_http ? 'insecure_http_enabled' : 'insecure_http_disabled','success',$who,{})
                    if $was_http != $allow_http;
                $dbh->commit or die 'Commit failed';
                1;
            } or do {
                eval { $dbh->rollback unless $dbh->{AutoCommit} };
                push @errors,'Configuration could not be saved.';
            };
            $saved = !@errors;
        }
        $config = $clean;
    }
    my $template = $self->get_template({file=>'configure.tt'});
    $template->param(%$config, errors=>\@errors, saved=>$saved, $self->_form_params($cgi),
        insecure_http=>$allow_http, insecure_http_from_server=>insecure_http_enabled(), https=>_https() ? 1:0,
        secret_configured=>$self->retrieve_data('client_secret_hash') ? 1:0);
    $self->output_html($template->output,undef,{force_no_caching=>1});
}

sub intranet_catalog_biblio_enhancements_toolbar_button {
    my ($self) = @_;
    return '' unless $self->_ready && $self->_transport_ok;
    # Verified upstream: TT calls this hook without arguments or a CGI object.
    my $cgi = CGI->new;
    my ($p) = $self->_staff($cgi);
    return '' unless $p && @{$self->_capabilities($p)};
    my $id = scalar $cgi->param('biblionumber');
    return '' unless valid_id($id) && Koha::Biblios->find($id);
    my $csrf = html_escape($self->_csrf($cgi));
    my $label = html_escape($self->retrieve_data('button_label'));
    my $class = html_escape(ref $self);
    return qq{<div class="btn-group" id="media-manager-action"><form method="post" action="/cgi-bin/koha/plugins/run.pl" style="display:inline">
<input type="hidden" name="class" value="$class"><input type="hidden" name="method" value="tool">
<input type="hidden" name="op" value="cud-authorize"><input type="hidden" name="csrf_token" value="$csrf">
<input type="hidden" name="biblionumber" value="$id">
<button class="btn btn-default" type="submit"><i class="fa fa-upload" aria-hidden="true"></i> $label</button></form></div>};
}

sub tool {
    my ($self) = @_;
    my $cgi = $self->{cgi};
    my $op = scalar($cgi->param('op')) // '';
    my $ok = eval {
        if ($op eq 'cud-authorize') { $self->_authorize($cgi); }
        elsif ($op eq 'continue') { $self->_continue($cgi); }
        elsif ($op eq 'cud-complete') { $self->_complete($cgi); }
        elsif ($op eq 'redirect') { $self->_error('Protocol retired','Legacy HMAC handoff is disabled. Use the updated catalogue toolbar.',400); }
        else {
            # `return` inside eval leaves the eval, so return 1 after rendering an
            # error: otherwise a second "Service unavailable" page would be printed.
            unless ($self->_admin($cgi)) {
                $self->_error('Access denied','Only superlibrarians may view audit and diagnostics.',403);
                return 1;
            }
            my $health;
            if ($op eq 'cud-test') {
                unless ($self->_valid_post($cgi)) {
                    $self->_error('Invalid request','CSRF validation failed.',403);
                    return 1;
                }
                if ($self->_ready) {
                    $health = Koha::Plugin::Com::Library::MediaManager::Health->check({%{$self->_config},insecure_http=>$self->_insecure_http});
                } else { $health = {reachable=>0,compatible=>0,message=>'Complete configuration first.'}; }
                $self->_audit($health->{reachable} ? 'connection_test_success':'connection_test_failed',
                    $health->{reachable} ? 'success':'failed',{userid=>C4::Context->userenv->{userid},patron_id=>C4::Context->userenv->{number}},{});
            }
            $self->_dashboard($cgi,$health);
        }
        1;
    };
    return $self->_error('Service unavailable','The integration could not complete the request. Contact the Koha administrator.',503) unless $ok;
}

sub _authorize {
    my ($self,$cgi) = @_;
    return $self->_error('HTTPS required','Use the HTTPS staff interface.',400) unless $self->_transport_ok;
    return $self->_error('Invalid request','A valid staff POST with CSRF protection is required.',403) unless $self->_valid_post($cgi);
    my ($p,$session) = $self->_staff($cgi);
    return $self->_error('Authentication required','Sign into the staff interface.',401) unless $p;
    my $ctx = {userid=>$p->userid,patron_id=>$p->borrowernumber,correlation_id=>random_hex()};
    $self->_audit('sso_authorization_started','started',$ctx,{});
    return $self->_error('Not configured','The administrator must configure protocol v2.',503) unless $self->_ready;
    unless (@{$self->_capabilities($p)}) {
        $self->_audit('permission_denied','denied',$ctx,{});
        return $self->_error('Access denied','Required staff permissions are missing.',403);
    }
    return $self->_error('Too many requests','Try again in one minute.',429) unless $self->_rate('staff:'.$p->borrowernumber,20);
    my $id = scalar $cgi->param('biblionumber');
    return $self->_error('Invalid record','Choose an existing bibliographic record.',400) unless valid_id($id);
    return $self->_error('Record unavailable','This bibliographic record is unavailable.',404) unless Koha::Biblios->find($id);
    $ctx->{biblio_id} = 0+$id;
    my $cfg = $self->_config;
    my $request = random_hex();
    my $dbh = $self->_db;
    my $table = $self->_table('requests');
    $dbh->do("INSERT INTO $table (request_hash,session_hash,patron_id,biblio_id,branch,binding,expires_at,correlation_id) VALUES (?,?,?,?,?,?,UNIX_TIMESTAMP()+120,?)",
        undef,sha256_hex($request),sha256_hex(scalar $cgi->cookie('CGISESSID')),
        $p->borrowernumber,$id,C4::Context->userenv->{branch} // '',_binding($cfg),$ctx->{correlation_id})
        or die 'Cannot store initiation';
    print $cgi->redirect(-uri=>$cfg->{mam_url}.'/sso/koha/start?request='.$request,
        -status=>'303 See Other', -Cache_Control=>'no-store', -Pragma=>'no-cache', -Referrer_Policy=>'no-referrer');
    return;
}

sub _binding {
    my ($cfg) = @_;
    return sha256_hex(join "\0",@$cfg{qw(mam_url instance_id client_id)});
}

sub _continue {
    my ($self,$cgi) = @_;
    my ($p) = $self->_staff($cgi);
    return $self->_error('Access denied','A valid HTTPS staff session is required.',403)
        unless $p && $self->_transport_ok;
    my $request = scalar($cgi->param('request')) // '';
    my $state = scalar($cgi->param('state')) // '';
    return $self->_error('Invalid request','Invalid browser binding.',400)
        unless $request =~ /\A[0-9a-f]{64}\z/ && $state =~ /\A[A-Za-z0-9_-]{43,128}\z/;
    # Cross-site top-level GET carries SameSite=Lax staff cookies. The local POST
    # then uses Koha CSRF protection; no grant is created by this GET.
    my $template = $self->get_template({file=>'continue.tt'});
    $template->param(request=>$request,state=>$state,$self->_form_params($cgi));
    $self->output_html($template->output,undef,{force_no_caching=>1});
}

sub _complete {
    my ($self,$cgi) = @_;
    return $self->_error('Invalid request','A valid HTTPS POST is required.',403)
        unless $self->_transport_ok && $self->_valid_post($cgi);
    my ($p) = $self->_staff($cgi);
    return $self->_error('Access denied','Staff authorization is unavailable.',403)
        unless $p && $self->_ready && @{$self->_capabilities($p)};
    my $request = scalar($cgi->param('request')) // '';
    my $state = scalar($cgi->param('state')) // '';
    return $self->_error('Invalid request','Invalid browser binding.',400)
        unless $request =~ /\A[0-9a-f]{64}\z/ && $state =~ /\A[A-Za-z0-9_-]{43,128}\z/;
    my $cfg = $self->_config;
    my $dbh = $self->_db;
    my $table = $self->_table('requests');
    my $code = random_hex();
    my $ok = eval {
        $dbh->begin_work or die 'Cannot begin';
        my $row = $dbh->selectrow_hashref("SELECT *,UNIX_TIMESTAMP() AS now_epoch FROM $table WHERE request_hash=? FOR UPDATE",
            undef,sha256_hex($request));
        die 'Invalid initiation' unless $row && !defined($row->{consumed_at})
            && $row->{expires_at} > $row->{now_epoch}
            && $row->{session_hash} eq sha256_hex(scalar $cgi->cookie('CGISESSID'))
            && $row->{patron_id} == $p->borrowernumber && $row->{binding} eq _binding($cfg)
            && Koha::Biblios->find($row->{biblio_id});
        $dbh->do("UPDATE $table SET consumed_at=UNIX_TIMESTAMP() WHERE request_hash=?",undef,sha256_hex($request))
            or die 'Cannot consume initiation';
        $self->_store->issue($code,{
            patron_id=>$p->borrowernumber,biblio_id=>$row->{biblio_id},branch=>$row->{branch},
            issuer=>$cfg->{instance_id},audience=>'media-manager',client_id=>$cfg->{client_id},
            ttl=>$cfg->{code_ttl},correlation_id=>$row->{correlation_id},browser_state=>$state,
        });
        $self->_audit('sso_authorization_issued','success',{
            userid=>$p->userid,patron_id=>$p->borrowernumber,biblio_id=>$row->{biblio_id},
            correlation_id=>$row->{correlation_id},
        },{transport=>_https() ? 'https' : 'insecure_http_test'});
        $dbh->commit or die 'Cannot commit';
        1;
    };
    unless ($ok) {
        eval { $dbh->rollback unless $dbh->{AutoCommit} };
        $self->_audit('sso_exchange_failed','failed',{userid=>$p->userid,patron_id=>$p->borrowernumber},{reason=>'browser_binding_failed'});
        return $self->_error('Handoff unavailable','The initiation expired, was already used, or belongs to another staff session. Start again from the catalogue.',400);
    }
    print $cgi->redirect(-uri=>$cfg->{mam_url}.'/sso/koha?code='.$code.'&state='.$state,
        -status=>'303 See Other', -Cache_Control=>'no-store', -Pragma=>'no-cache', -Referrer_Policy=>'no-referrer');
    return;
}

sub _store {
    my ($self) = @_;
    return Koha::Plugin::Com::Library::MediaManager::Store->new($self->_db,$self->_table('codes'));
}

sub exchange {
    my ($self,$body,$client,$secret,$ip) = @_;
    my $ctx = {source_ip=>$ip,correlation_id=>random_hex()};
    return (503,{error=>'temporarily_unavailable'}) unless $self->is_enabled && $self->_ready;
    unless ($self->_rate('exchange:global',600) && $self->_rate('exchange:'.$ip,60)) {
        return (429,{error=>'rate_limited'});
    }
    my ($now) = $self->_db->selectrow_array('SELECT UNIX_TIMESTAMP()');
    my $authenticated = defined($client) && $client eq $self->retrieve_data('client_id')
        && (secret_matches($secret,$self->retrieve_data('client_secret_hash'))
        || (($self->retrieve_data('previous_secret_until') // 0) > $now
            && secret_matches($secret,$self->retrieve_data('previous_secret_hash'))));
    unless ($authenticated) {
        $self->_audit('sso_exchange_failed','failed',$ctx,{reason=>'invalid_client'});
        return (401,{error=>'invalid_client'});
    }
    unless (ref($body) eq 'HASH' && keys(%$body) == 1 && defined($body->{code})
        && !ref($body->{code}) && $body->{code} =~ /\A[0-9a-f]{64}\z/) {
        $self->_audit('sso_exchange_failed','failed',$ctx,{reason=>'invalid_request'});
        return (400,{error=>'invalid_request'});
    }
    my $cfg = $self->_config;
    my ($status,$response) = $self->_store->consume($body->{code},
        {issuer=>$cfg->{instance_id},audience=>'media-manager',client_id=>$client},
        sub {
            my ($row) = @_;
            my $p = $self->_patron($row->{patron_id});
            return unless $p && Koha::Biblios->find($row->{biblio_id});
            $ctx->{userid} = $p->userid;
            my $caps = $self->_capabilities($p);
            return unless @$caps;
            return {
                success=>JSON::PP::true, protocol=>'code-v2', iss=>$row->{issuer}, aud=>$row->{audience},
                identity=>{provider=>'koha',instance=>$row->{issuer},patron_id=>0+$p->borrowernumber,userid=>$p->userid},
                context=>{biblio_id=>0+$row->{biblio_id},branch=>$row->{branch}},
                capabilities=>$caps,issued_at=>0+$row->{issued_at},expires_at=>0+$row->{expires_at},
                correlation_id=>$row->{correlation_id},state=>$row->{browser_state},
            };
        },
        sub {
            my ($result,$row) = @_;
            my %event = (success=>'sso_exchange_success',replay=>'sso_replay_rejected',
                expired=>'sso_code_expired',permission_denied=>'permission_denied');
            my $event_ctx = {%$ctx};
            if ($row) { @$event_ctx{qw(patron_id biblio_id correlation_id)} = @$row{qw(patron_id biblio_id correlation_id)}; }
            $self->_audit($event{$result} // 'sso_exchange_failed',$result eq 'success' ? 'success':'failed',$event_ctx,{});
        });
    return (200,$response) if $status eq 'success';
    return (403,{error=>'access_denied'}) if $status eq 'permission_denied';
    return (400,{error=>'invalid_grant'});
}

sub api_namespace { return 'media-manager'; }
sub api_routes {
    my ($self) = @_;
    open my $fh,'<:raw',$self->mbf_path('openapi.json') or die 'Missing route schema';
    local $/;
    return decode_json(<$fh>);
}

sub _dashboard {
    my ($self,$cgi,$health) = @_;
    my $per_page = 20;
    my $page = scalar($cgi->param('page')) // 1;
    $page = 1 unless $page =~ /\A[1-9][0-9]{0,4}\z/;
    my $action = scalar($cgi->param('event')) // '';
    $action = '' unless $action =~ /\A[a-z_]{1,50}\z/;
    my $t = $self->_table('log');
    my $where = $action ? ' WHERE action=?' : '';
    my @bind = $action ? ($action) : ();
    my ($total) = $self->_db->selectrow_array("SELECT COUNT(*) FROM $t$where",undef,@bind);
    $total ||= 0;
    my $pages = $total ? int(($total + $per_page - 1) / $per_page) : 1;
    $page = $pages if $page > $pages;
    my $logs = $self->_db->selectall_arrayref(
        "SELECT *, UNIX_TIMESTAMP(created_at) AS event_epoch FROM $t$where ORDER BY id DESC LIMIT ? OFFSET ?",
        {Slice=>{}},@bind,$per_page,($page-1)*$per_page) || [];
    $_->{utc_time} = strftime('%Y-%m-%d %H:%M:%S UTC',gmtime($_->{event_epoch})) for @$logs;
    # Page numbers shown around the current page (first and last are always offered as links).
    my $from = $page - 2 < 1 ? 1 : $page - 2;
    my $to = $from + 4 > $pages ? $pages : $from + 4;
    $from = $to - 4 < 1 ? 1 : $to - 4;
    my $storage = eval {
        for my $name (qw(log requests codes rates)) {
            $self->_db->selectrow_array('SELECT COUNT(*) FROM '.$self->_table($name).' WHERE 1=0');
        }
        1;
    };
    my $template = $self->get_template({file=>'tool.tt'});
    $template->param(%{$self->_config},is_configured=>$self->_ready,storage_ok=>$storage ? 1:0,
        logs=>$logs,page=>$page,pages=>$pages,total=>$total,page_numbers=>[$from..$to],
        first_row=>$total ? ($page-1)*$per_page+1 : 0, last_row=>($page-1)*$per_page+scalar(@$logs),
        previous=>$page-1,next=>$page < $pages ? $page+1 : 0,event=>$action,
        page_base=>'/cgi-bin/koha/plugins/run.pl?class='.uri_escape(__PACKAGE__).'&method=tool&event='.uri_escape($action).'&page=',
        insecure_http=>$self->_insecure_http,
        health=>$health,$self->_form_params($cgi));
    $self->output_html($template->output,undef,{force_no_caching=>1});
}

sub _error {
    my ($self,$title,$message,$status) = @_;
    my $template = $self->get_template({file=>'error.tt'});
    $template->param(error_title=>$title,error_message=>$message);
    $self->output_html($template->output,($status // 400).' Error',{force_no_caching=>1});
    return;
}

sub maintenance {
    my ($self) = @_;
    my $days = $self->retrieve_data('audit_retention') // 90;
    die 'Invalid retention' unless $days =~ /\A[0-9]{1,4}\z/ && $days >= 1 && $days <= 3650;
    my $dbh = $self->_db;
    # Bounded batches, run only by the explicitly installed maintenance command.
    for my $spec (
        ['log','created_at < DATE_SUB(NOW(), INTERVAL ? DAY)',$days],
        ['codes','expires_at < UNIX_TIMESTAMP()-?',86400],
        ['requests','expires_at < UNIX_TIMESTAMP()-?',86400],
        ['rates','window_id < FLOOR(UNIX_TIMESTAMP()/60)-?',60],
    ) {
        my ($name,$predicate,$value) = @$spec;
        my $t = $self->_table($name);
        for (1..100) {
            my $rows = $dbh->do("DELETE FROM $t WHERE $predicate LIMIT 1000",undef,$value);
            die 'Maintenance failed' unless defined $rows;
            last if $rows < 1000;
        }
    }
    return 1;
}
1;
