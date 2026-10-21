package Koha::Plugin::Com::Library::MediaManager;

## ═══════════════════════════════════════════════════════════════════
##  Media Asset Management (MAM) – Koha Plugin
##
##  Provides HMAC-signed SSO from the Koha staff interface to a
##  Media Asset Management (MAM) application. Injects "Upload Secure Media"
##  buttons on bibliographic detail pages, logs every redirect for
##  audit purposes, and includes a health-check dashboard.
##
##  Compatible with Koha 22.11 – 26.05+
## ═══════════════════════════════════════════════════════════════════

use Modern::Perl;
use base qw(Koha::Plugins::Base);

use C4::Context;
use C4::Auth qw( haspermission );
use Digest::SHA qw( hmac_sha256_hex );
use URI::Escape qw( uri_escape_utf8 );
use HTTP::Tiny;

our $VERSION = "1.0.0";

our $metadata = {
    name            => 'Media Asset Management (MAM)',
    author          => 'Tahir Ali Channa',
    description     => 'SSO integration with the Media Asset Management (MAM) application. '
                     . 'Adds secure upload buttons to bibliographic detail pages, '
                     . 'handles HMAC-signed authentication, and provides audit logging.',
    date_authored   => '2026-10-21',
    date_updated    => '2026-10-21',
    minimum_version => '22.1100000',
    maximum_version => undef,
    version         => $VERSION,
};

# ─────────────────────────────────────────────────────────────────────
#  Constructor
# ─────────────────────────────────────────────────────────────────────

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'}            = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);
    return $self;
}

# ─────────────────────────────────────────────────────────────────────
#  Lifecycle Hooks
# ─────────────────────────────────────────────────────────────────────

sub install {
    my ( $self, $args ) = @_;

    my $dbh       = C4::Context->dbh;
    my $log_table = $self->get_qualified_table_name('log');

    $dbh->do(qq{
        CREATE TABLE IF NOT EXISTS `$log_table` (
            `id`             INT AUTO_INCREMENT PRIMARY KEY,
            `userid`         VARCHAR(75)  NOT NULL,
            `borrowernumber` INT          DEFAULT NULL,
            `biblionumber`   INT          DEFAULT NULL,
            `action`         VARCHAR(50)  NOT NULL DEFAULT 'sso_redirect',
            `ip_address`     VARCHAR(45)  DEFAULT NULL,
            `status`         VARCHAR(20)  NOT NULL DEFAULT 'success',
            `details`        TEXT         DEFAULT NULL,
            `created_at`     TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_mm_userid`       (`userid`),
            INDEX `idx_mm_biblionumber` (`biblionumber`),
            INDEX `idx_mm_created_at`   (`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    }) or warn "MediaManager install: could not create log table – $DBI::errstr";

    # Sensible defaults (only written on first install)
    $self->store_data({
        token_ttl           => '300',
        button_label        => 'Upload Secure Media',
        allowed_permissions => 'editcatalogue,superlibrarian',
    });

    return 1;
}

sub upgrade {
    my ( $self, $args ) = @_;

    my $dbh       = C4::Context->dbh;
    my $log_table = $self->get_qualified_table_name('log');

    # Ensure the log table exists when upgrading an existing installation.
    $dbh->do(qq{
        CREATE TABLE IF NOT EXISTS `$log_table` (
            `id`             INT AUTO_INCREMENT PRIMARY KEY,
            `userid`         VARCHAR(75)  NOT NULL,
            `borrowernumber` INT          DEFAULT NULL,
            `biblionumber`   INT          DEFAULT NULL,
            `action`         VARCHAR(50)  NOT NULL DEFAULT 'sso_redirect',
            `ip_address`     VARCHAR(45)  DEFAULT NULL,
            `status`         VARCHAR(20)  NOT NULL DEFAULT 'success',
            `details`        TEXT         DEFAULT NULL,
            `created_at`     TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            INDEX `idx_mm_userid`       (`userid`),
            INDEX `idx_mm_biblionumber` (`biblionumber`),
            INDEX `idx_mm_created_at`   (`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    });

    # Back-fill defaults that may not exist in older installs
    $self->store_data({ token_ttl           => '300' })
        unless defined $self->retrieve_data('token_ttl');
    $self->store_data({ button_label        => 'Upload Secure Media' })
        unless defined $self->retrieve_data('button_label');
    $self->store_data({ allowed_permissions => 'editcatalogue,superlibrarian' })
        unless defined $self->retrieve_data('allowed_permissions');

    $self->store_data({ last_upgraded => '' . localtime() });

    return 1;
}

sub uninstall {
    my ( $self, $args ) = @_;

    my $dbh       = C4::Context->dbh;
    my $log_table = $self->get_qualified_table_name('log');

    $dbh->do("DROP TABLE IF EXISTS `$log_table`");

    # Rows in plugin_data for this class are deleted automatically by
    # Koha core on uninstall – no manual cleanup required.

    return 1;
}

# ─────────────────────────────────────────────────────────────────────
#  Configuration
# ─────────────────────────────────────────────────────────────────────

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    if ( scalar $cgi->param('save') ) {
        $self->store_data({
            mam_url         => scalar $cgi->param('mam_url'),
            shared_secret       => scalar $cgi->param('shared_secret'),
            token_ttl           => scalar $cgi->param('token_ttl')           || '300',
            button_label        => scalar $cgi->param('button_label')        || 'Upload Secure Media',
            allowed_permissions => scalar $cgi->param('allowed_permissions') || 'editcatalogue,superlibrarian',
        });
        $self->go_home();
        return;
    }

    my $template = $self->get_template({ file => 'configure.tt' });
    $template->param(
        mam_url         => $self->retrieve_data('mam_url')         // '',
        shared_secret       => $self->retrieve_data('shared_secret')       // '',
        token_ttl           => $self->retrieve_data('token_ttl')           // '300',
        button_label        => $self->retrieve_data('button_label')        // 'Upload Secure Media',
        allowed_permissions => $self->retrieve_data('allowed_permissions') // 'editcatalogue,superlibrarian',
        CLASS               => $self->{'metadata'}->{'class'},
    );
    $self->output_html( $template->output() );
}

# ─────────────────────────────────────────────────────────────────────
#  UI Injection Hooks
# ─────────────────────────────────────────────────────────────────────

## JavaScript hook – universally supported across Koha versions.
## Injects the toolbar button via DOM manipulation; skips if the native
## toolbar-button hook (below) already rendered one.

sub intranet_js {
    my ($self) = @_;

    my $class        = $self->{'metadata'}->{'class'};
    my $button_label = $self->retrieve_data('button_label') // 'Upload Secure Media';

    # Sanitise for safe embedding inside a JS string literal
    $button_label =~ s/&/\&amp;/g;
    $button_label =~ s/</\&lt;/g;
    $button_label =~ s/>/\&gt;/g;
    $button_label =~ s/'/\\'/g;

    return <<"JAVASCRIPT";
<script>
\$(document).ready(function(){
    /* Only act on the catalogue detail page */
    if(window.location.pathname.indexOf('/catalogue/detail.pl')===-1) return;

    /* If the native toolbar-button hook already rendered our button, bail */
    if(document.getElementById('media-manager-btn')) return;

    var urlParams = new URLSearchParams(window.location.search);
    var biblioId  = urlParams.get('biblionumber');
    if(!biblioId) return;

    var btn = '<a class="btn btn-default btn-sm" id="media-manager-btn" '
        + 'href="/cgi-bin/koha/plugins/run.pl?class=$class'
        + '&method=tool&op=redirect&biblionumber=' + encodeURIComponent(biblioId) + '">'
        + '<i class="fa fa-upload"></i> $button_label</a>';

    \$('#toolbar').append(btn);
});
</script>
JAVASCRIPT
}

## Native toolbar-button hook – available in Koha >= 23.11.
## Koha calls this automatically when rendering the biblio detail toolbar
## and injects the returned HTML. The id="media-manager-btn" attribute
## prevents the intranet_js fallback from adding a duplicate.

sub intranet_catalog_biblio_enhancements_toolbar_button {
    my ( $self, $args ) = @_;

    my $biblionumber = $args->{'biblionumber'};
    return '' unless $biblionumber;

    my $class        = $self->{'metadata'}->{'class'};
    my $button_label = $self->retrieve_data('button_label') // 'Upload Secure Media';

    # HTML-escape the label
    $button_label =~ s/&/&amp;/g;
    $button_label =~ s/</&lt;/g;
    $button_label =~ s/>/&gt;/g;
    $button_label =~ s/"/&quot;/g;

    my $url = '/cgi-bin/koha/plugins/run.pl?class=' . uri_escape_utf8($class)
            . '&method=tool&op=redirect&biblionumber='  . uri_escape_utf8($biblionumber);

    return qq{
        <a class="btn btn-default btn-sm" id="media-manager-btn" href="$url">
            <i class="fa fa-upload" aria-hidden="true"></i> $button_label
        </a>
    };
}

# ─────────────────────────────────────────────────────────────────────
#  Tool Entry-Point (Router)
# ─────────────────────────────────────────────────────────────────────

sub tool {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};
    my $op  = scalar( $cgi->param('op') ) // '';

    if    ( $op eq 'redirect' )        { $self->_handle_sso_redirect($cgi) }
    elsif ( $op eq 'test_connection' ) { $self->_handle_connection_test($cgi) }
    else                               { $self->_show_dashboard($cgi) }
}

# ─────────────────────────────────────────────────────────────────────
#  Private: SSO Redirect
# ─────────────────────────────────────────────────────────────────────

sub _handle_sso_redirect {
    my ( $self, $cgi ) = @_;

    my $mam_url   = $self->retrieve_data('mam_url')         // '';
    my $secret        = $self->retrieve_data('shared_secret')       // '';
    my $token_ttl     = $self->retrieve_data('token_ttl')           // 300;
    my $allowed_perms = $self->retrieve_data('allowed_permissions') // 'editcatalogue,superlibrarian';

    # ── Guard: plugin must be configured ─────────────────────────────
    unless ( $mam_url && $secret ) {
        return $self->_render_error(
            'Plugin Not Configured',
            'Please set the MAM URL and Shared Secret in the plugin configuration.',
            { show_configure_link => 1 },
        );
    }

    # ── Guard: user must be logged in ────────────────────────────────
    my $userenv = C4::Context->userenv;
    unless ( $userenv && $userenv->{'userid'} ) {
        return $self->_render_error(
            'Authentication Required',
            'You must be logged in to the Koha staff interface to use Media Asset Management (MAM).',
        );
    }

    my $userid         = $userenv->{'userid'};
    my $borrowernumber = $userenv->{'number'}    // '';
    my $firstname      = $userenv->{'firstname'} // '';
    my $surname        = $userenv->{'surname'}   // '';
    my $branch         = $userenv->{'branch'}    // '';

    # ── Guard: permission check ──────────────────────────────────────
    unless ( $self->_user_has_permission( $userid, $allowed_perms ) ) {
        $self->_log_event({
            userid         => $userid,
            borrowernumber => $borrowernumber,
            biblionumber   => scalar $cgi->param('biblionumber'),
            action         => 'sso_redirect',
            status         => 'denied',
            details        => "Insufficient permissions (requires: $allowed_perms)",
        });
        return $self->_render_error(
            'Access Denied',
            'You do not have the required permissions to use Media Asset Management (MAM).',
            { required_permissions => $allowed_perms },
        );
    }

    # ── Guard: valid biblionumber ────────────────────────────────────
    my $biblionumber = scalar( $cgi->param('biblionumber') ) // '';
    unless ( $biblionumber =~ /^\d+$/ ) {
        return $self->_render_error(
            'Invalid Record',
            'A valid bibliographic record number is required to proceed.',
        );
    }

    # ── Build HMAC-SHA256 signed payload ─────────────────────────────
    #
    #  Payload format:  userid|borrowernumber|biblionumber|timestamp
    #
    #  MAM must reconstruct the same string from the query
    #  parameters and verify the signature with the shared secret.
    #  The timestamp + TTL allow MAM to reject expired tokens.
    #
    my $timestamp = time();
    my $payload   = join( '|', $userid, $borrowernumber, $biblionumber, $timestamp );
    my $signature = hmac_sha256_hex( $payload, $secret );

    # ── Audit log ────────────────────────────────────────────────────
    $self->_log_event({
        userid         => $userid,
        borrowernumber => $borrowernumber,
        biblionumber   => $biblionumber,
        action         => 'sso_redirect',
        status         => 'success',
        details        => "TTL=${token_ttl}s",
    });

    # ── Redirect to MAM SSO endpoint ─────────────────────────────
    my $redirect_url = sprintf(
        '%s/sso/koha?userid=%s&borrowernumber=%s&biblio_id=%s&timestamp=%s&ttl=%s&name=%s&branch=%s&signature=%s',
        $mam_url,
        uri_escape_utf8($userid),
        uri_escape_utf8($borrowernumber),
        uri_escape_utf8($biblionumber),
        uri_escape_utf8($timestamp),
        uri_escape_utf8($token_ttl),
        uri_escape_utf8("$firstname $surname"),
        uri_escape_utf8($branch),
        uri_escape_utf8($signature),
    );

    print $cgi->redirect($redirect_url);
    exit;    # Required: prevents run.pl from emitting further output
}

# ─────────────────────────────────────────────────────────────────────
#  Private: Dashboard
# ─────────────────────────────────────────────────────────────────────

sub _show_dashboard {
    my ( $self, $cgi, $extra_params ) = @_;

    my $mam_url   = $self->retrieve_data('mam_url')         // '';
    my $secret        = $self->retrieve_data('shared_secret')       // '';
    my $token_ttl     = $self->retrieve_data('token_ttl')           // '300';
    my $button_label  = $self->retrieve_data('button_label')        // 'Upload Secure Media';
    my $allowed_perms = $self->retrieve_data('allowed_permissions') // '';
    my $is_configured = ( $mam_url && $secret ) ? 1 : 0;

    my $logs = $self->_fetch_recent_logs(50);

    my $template = $self->get_template({ file => 'tool.tt' });
    $template->param(
        is_configured => $is_configured,
        mam_url   => $mam_url,
        token_ttl     => $token_ttl,
        button_label  => $button_label,
        allowed_perms => $allowed_perms,
        logs          => $logs,
        CLASS         => $self->{'metadata'}->{'class'},
        %{ $extra_params // {} },
    );
    $self->output_html( $template->output() );
}

# ─────────────────────────────────────────────────────────────────────
#  Private: Connection Test
# ─────────────────────────────────────────────────────────────────────

sub _handle_connection_test {
    my ( $self, $cgi ) = @_;

    my $mam_url = $self->retrieve_data('mam_url') // '';
    my ( $test_success, $test_message ) = ( 0, '' );

    if ( !$mam_url ) {
        $test_message = 'MAM URL is not configured.';
    }
    else {
        eval {
            my $http     = HTTP::Tiny->new( timeout => 10 );
            my $response = $http->get($mam_url);

            if ( $response->{success} ) {
                $test_success = 1;
                $test_message = "Connection successful (HTTP $response->{status}).";
            }
            else {
                $test_message = "HTTP $response->{status} – $response->{reason}";
            }
        };
        if ($@) {
            $test_message = "Connection error: $@";
        }
    }

    # Audit log
    my $userenv = C4::Context->userenv;
    if ($userenv) {
        $self->_log_event({
            userid         => $userenv->{'userid'},
            borrowernumber => $userenv->{'number'},
            action         => 'connection_test',
            status         => $test_success ? 'success' : 'failed',
            details        => $test_message,
        });
    }

    return $self->_show_dashboard(
        $cgi,
        {
            test_performed => 1,
            test_success   => $test_success,
            test_message   => $test_message,
        },
    );
}

# ─────────────────────────────────────────────────────────────────────
#  Private: Error Page
# ─────────────────────────────────────────────────────────────────────

sub _render_error {
    my ( $self, $title, $message, $extra ) = @_;

    my $template = $self->get_template({ file => 'error.tt' });
    $template->param(
        error_title   => $title,
        error_message => $message,
        CLASS         => $self->{'metadata'}->{'class'},
        %{ $extra // {} },
    );
    $self->output_html( $template->output() );
}

# ─────────────────────────────────────────────────────────────────────
#  Private: Permission Helper
# ─────────────────────────────────────────────────────────────────────

sub _user_has_permission {
    my ( $self, $userid, $allowed_perms_csv ) = @_;

    my $userenv = C4::Context->userenv;
    return 0 unless $userenv;

    # Superlibrarians always pass (bit 0 of the flags bitmask)
    my $flags = $userenv->{'flags'} // 0;
    return 1 if ( $flags & 1 );

    my @allowed = split( /\s*,\s*/, $allowed_perms_csv );

    for my $perm (@allowed) {
        next unless $perm;
        next if lc($perm) eq 'superlibrarian';    # already checked

        my $has = eval { haspermission( $userid, { $perm => '*' } ) };
        return 1 if $has;
    }

    return 0;
}

# ─────────────────────────────────────────────────────────────────────
#  Private: Audit Logging
# ─────────────────────────────────────────────────────────────────────

sub _log_event {
    my ( $self, $params ) = @_;

    my $dbh       = C4::Context->dbh;
    my $log_table = $self->get_qualified_table_name('log');

    eval {
        my $sth = $dbh->prepare(qq{
            INSERT INTO `$log_table`
                (userid, borrowernumber, biblionumber, action, ip_address, status, details)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        });
        $sth->execute(
            $params->{userid},
            $params->{borrowernumber},
            $params->{biblionumber},
            $params->{action}     // 'unknown',
            $params->{ip_address} // $ENV{'REMOTE_ADDR'} // '0.0.0.0',
            $params->{status}     // 'success',
            $params->{details},
        );

        # Probabilistic housekeeping: purge rows > 90 days old on ~5 %
        # of inserts to keep the table bounded without running a cron.
        if ( int( rand(20) ) == 0 ) {
            $dbh->do(qq{
                DELETE FROM `$log_table`
                WHERE  created_at < DATE_SUB( NOW(), INTERVAL 90 DAY )
            });
        }
    };
    if ($@) {
        warn "MediaManager: failed to log event – $@";
    }
}

sub _fetch_recent_logs {
    my ( $self, $limit ) = @_;
    $limit //= 50;

    my $dbh       = C4::Context->dbh;
    my $log_table = $self->get_qualified_table_name('log');
    my $logs      = [];

    eval {
        my $sth = $dbh->prepare(qq{
            SELECT id, userid, borrowernumber, biblionumber,
                   action, ip_address, status, details, created_at
            FROM   `$log_table`
            ORDER  BY created_at DESC
            LIMIT  ?
        });
        $sth->execute($limit);
        while ( my $row = $sth->fetchrow_hashref ) {
            push @{$logs}, $row;
        }
    };
    if ($@) {
        warn "MediaManager: failed to fetch logs – $@";
    }

    return $logs;
}

1;
