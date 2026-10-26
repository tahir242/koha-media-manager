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
like($html,qr/target="_blank" rel="noopener"/,'MAM opens in a new tab without opener access');
like($html,qr/opens in a new tab/,'new tab announced to screen readers');
{
    my $old=Koha::Plugin::Com::Library::MediaManager->new({});
    $old->{data}={button_label=>'Upload Secure Media'};
    $old->_defaults;
    is($old->retrieve_data('button_label'),'Attach Media','old default label renamed on upgrade');
    $old->{data}={button_label=>'Add files'};
    $old->_defaults;
    is($old->retrieve_data('button_label'),'Add files','custom label kept on upgrade');
    $old->{data}={};
    $old->_defaults;
    is($old->retrieve_data('button_label'),'Attach Media','new install default');
}
ok($Koha::Plugins::Methods::rows{'Koha::Plugin::Com::Library::MediaManager intranet_js'},
    'toolbar hook registers intranet_js missed by an upgrade from a stale worker');
like($p->intranet_js({page=>'/cgi-bin/koha/cataloguing/additem.pl'}),qr/\A<script>/,'26.05 page hint identifies the add item page');
is($p->intranet_js,'','no item script outside the record and add/edit item pages');
{
    local $ENV{SCRIPT_NAME}='/cgi-bin/koha/catalogue/moredetail.pl';
    is($p->intranet_js,'','no item script on other catalogue pages');
}
{
    local $ENV{SCRIPT_NAME}='/cgi-bin/koha/catalogue/detail.pl';
    like($p->intranet_js,qr/\A<script>/,'item script on the record page (holdings Actions menus)');
    like($p->intranet_js({page=>'/cgi-bin/koha/catalogue/detail.pl'}),qr/getElementById\('catalog_detail'\)/,'script acts on the record page');
}
{
    local $ENV{SCRIPT_NAME}='/cgi-bin/koha/cataloguing/additem.pl';
    my $js=$p->intranet_js({page=>'additem'});
    like($js,qr/\A<script>/,'item script on additem.pl (26.05 page hash ignored)');
    like($js,qr/"biblionumber":123/,'script carries the validated record');
    like($js,qr/"csrf":"fixture-csrf"/,'script carries a CSRF token');
    like($js,qr/op:'cud-authorize'/,'item action posts the existing authorization');
    like($js,qr/itemnumber:itemnumber/,'item action sends the itemnumber');
    like($js,qr/getElementById\('cat_additem'\)/,'script acts on the add item page');
    like($js,qr/ul\.dropdown-menu/,'entries go into the item Actions menu');
    like($js,qr/MutationObserver/,'rows drawn later by DataTables get their entry');
    like($js,qr/btn btn-default btn-xs media-manager-item-action/,'button next to Edit when the holdings table has no menu');
    like($js,qr/links\[i\]\.after\(' ',a\)/,'fallback button sits beside the Edit link');
    unlike($js,qr/media-manager-editing|heading\.appendChild/,'no button in the edit item heading');
    unlike($js,qr/<script>'|<\/script>"/,'label cannot break out of the script');
    like($js,qr/Upload \\u003cscript\\u003e/,'label JSON-escaped');
    is(()=$js=~/<\/script>/g,1,'one script element');
    {
        local $CGI::params{biblionumber}=0;
        is($p->intranet_js,'','invalid biblio hides item actions');
    }
    {
        local $C4::Auth::permissions{edit_catalogue}=0;
        is($p->intranet_js,'','missing permission hides item actions');
    }
    {
        local $ENV{HTTPS}='';
        is($p->intranet_js,'','plain HTTP without test mode hides item actions');
    }
}
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
