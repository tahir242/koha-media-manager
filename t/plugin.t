use strict;
use warnings;
use Test::More;
use lib '.', 't/lib';
use MockKoha;
use Koha::Plugin::Com::Library::MediaManager;
use Koha::Plugin::Com::Library::MediaManager::Security qw(secret_hash);
my $p=Koha::Plugin::Com::Library::MediaManager->new({});
$p->{data}={mam_url=>'https://dam.example.org',instance_id=>'library',client_id=>'dam',
    code_ttl=>60,rotation_grace=>300,audit_retention=>90,button_label=>q{Upload <script>'"},
    staff_policy=>'cataloguers',health_ips=>'',protocol=>'code-v2',client_secret_hash=>secret_hash('a' x 64)};
ok($p->_ready,'v2 configured');
local $ENV{HTTPS}='on';
my $html=$p->intranet_catalog_biblio_enhancements_toolbar_button;
like($html,qr/name="biblionumber" value="123"/,'native hook gets CGI context with no arguments');
like($html,qr/method="post"/,'native action is POST');
like($html,qr/name="csrf_token"/,'native action includes CSRF');
unlike($html,qr/<script>/,'label escaped');
is(()=$html=~/id="media-manager-action"/g,1,'one native button');
ok(!$p->can('intranet_js'),'no duplicate JS insertion path');
{
    local $CGI::params{biblionumber}=0;
    is($p->intranet_catalog_biblio_enhancements_toolbar_button,'','invalid biblio hides action');
}
{
    local $Koha::Biblios::exists=0;
    is($p->intranet_catalog_biblio_enhancements_toolbar_button,'','deleted biblio hides action');
}
{
    local $C4::Auth::permissions{edit_catalogue}=0;
    is_deeply($p->_capabilities($Koha::Patrons::patron),[],'missing catalogue subpermission fails closed');
}
{
    local $Koha::Patrons::patron->{flags}=1;
    is_deeply($p->_capabilities($Koha::Patrons::patron),[qw(media.access media.upload media.manage media.admin)],'superlibrarian capabilities');
}
{
    local $CGI::cookie='';
    ok(!$p->_staff(CGI->new),'missing session rejected');
}
{
    local $C4::Auth::session->{interface}='opac';
    ok(!$p->_staff(CGI->new),'OPAC session rejected');
}
{
    local $Koha::Patrons::patron->{locked}=1;
    ok(!$p->_patron(7),'locked staff rejected');
}
{
    local $Koha::Patrons::patron->{expired}=1;
    ok(!$p->_patron(7),'expired staff rejected');
}
{
    local $Koha::Token::valid=0;
    ok(!$p->_valid_post(CGI->new),'bad CSRF rejected');
}
{
    local $CGI::method='GET';
    ok(!$p->_valid_post(CGI->new),'GET mutation rejected');
}
my $health=Koha::Plugin::Com::Library::MediaManager::Health->check($p->_config);
ok(!$health->{reachable},'health disabled without IP authorization');
my $routes=$p->api_routes;
ok($routes->{'/exchange'}{post},'native REST exchange declared');
# Koha resolves plugin controllers under its "Koha::Plugin" route namespace, so x-mojo-to must be
# relative ("Com::...") — a fully qualified name becomes Koha::Plugin::Koha::Plugin::... (HTTP 500).
my $target=$routes->{'/exchange'}{post}{'x-mojo-to'};
is($target,'Com::Library::MediaManager::Controller#exchange','x-mojo-to is relative to Koha::Plugin');
my ($controller)=split /#/,$target;
(my $file="Koha/Plugin/$controller.pm") =~ s{::}{/}g;
ok(-f $file,"route target resolves to the real controller module ($file)");
ok(!exists $routes->{'/exchange'}{get},'no GET exchange');
done_testing;
