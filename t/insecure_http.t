use strict;
use warnings;
use Test::More;
use lib '.', 't/lib';
use MockKoha;
BEGIN {
    $INC{'Mojo/Base.pm'}=__FILE__;
    package Mojo::Base;
    sub import { }
}
use Koha::Plugin::Com::Library::MediaManager;
use Koha::Plugin::Com::Library::MediaManager::Controller;
use Koha::Plugin::Com::Library::MediaManager::Security qw(secret_hash validate_config insecure_http_enabled);
{
    package HttpController;
    sub res { $_[0] }
    sub req { $_[0] }
    sub headers { $_[0] }
    sub cache_control { }
    sub header { $_[0]->{headers}{$_[1]}=$_[2] if @_>2; $_[0]->{headers}{$_[1]} }
    sub url { $_[0] }
    sub to_abs { $_[0] }
    sub scheme { 'http' }
    sub body { '{}' }
    sub json { {code=>'c' x 64} }
    sub tx { $_[0] }
    sub remote_address { '192.0.2.1' }
    sub render { my ($s,%a)=@_; $s->{rendered}=\%a; }
}
my %cfg=(mam_url=>'http://10.1.89.51:8015',instance_id=>'library',client_id=>'dam',code_ttl=>60,
    rotation_grace=>300,audit_retention=>90,button_label=>'Upload',staff_policy=>'cataloguers',health_ips=>'');
my $p=Koha::Plugin::Com::Library::MediaManager->new({});
$p->{data}={%cfg,protocol=>'code-v2',client_secret_hash=>secret_hash('a' x 64)};
local $ENV{HTTPS}='off';

# Default: off. Production behaviour is unchanged.
ok(!insecure_http_enabled(),'test mode off unless configured');
my (undef,$errors)=validate_config({%cfg});
ok(@$errors,'HTTP application URL rejected by default');
ok(!$p->_ready,'HTTP configuration not ready by default');
ok(!$p->_transport_ok,'plain HTTP staff request refused by default');
is($p->intranet_catalog_biblio_enhancements_toolbar_button,'','no toolbar action over HTTP by default');
my $c=bless {},'HttpController';
Koha::Plugin::Com::Library::MediaManager::Controller::exchange($c);
is_deeply($c->{rendered}{json},{error=>'https_required'},'HTTP exchange refused by default');
for my $value ('0','no','',' ') {
    local $C4::Context::config{media_manager_insecure_http}=$value;
    ok(!insecure_http_enabled(),"value '$value' does not enable test mode");
}

# Enabled by the operator in koha-conf.xml.
{
    local $C4::Context::config{media_manager_insecure_http}='1';
    ok(insecure_http_enabled(),'koha-conf.xml switch enables test mode');
    (undef,$errors)=validate_config({%cfg},{allow_http=>1});
    is_deeply($errors,[],'HTTP IP:port application URL accepted in test mode');
    (undef,$errors)=validate_config({%cfg,mam_url=>'ftp://10.1.89.51'},{allow_http=>1});
    ok(@$errors,'other schemes still rejected');
    (undef,$errors)=validate_config({%cfg,mam_url=>'http://user:pass@10.1.89.51'},{allow_http=>1});
    ok(@$errors,'credentials in URL still rejected');
    ok($p->_ready,'HTTP configuration ready in test mode');
    ok($p->_transport_ok,'plain HTTP staff request allowed in test mode');
    like($p->intranet_catalog_biblio_enhancements_toolbar_button,qr/name="op" value="cud-authorize"/,'toolbar action shown in test mode');
    $c=bless {},'HttpController';
    {
        no warnings 'redefine';
        local *Koha::Plugin::Com::Library::MediaManager::exchange=sub { (401,{error=>'invalid_client'}) };
        Koha::Plugin::Com::Library::MediaManager::Controller::exchange($c);
    }
    is($c->{rendered}{status},401,'HTTP exchange reaches client authentication in test mode');
}

# Enabled by a superlibrarian with the "Allow HTTP" checkbox on the Configure page.
{
    package ToggleDB;
    sub begin_work { $_[0]->{AutoCommit}=0; 1 }
    sub selectrow_array { 1000 }
    sub commit { $_[0]->{AutoCommit}=1; 1 }
    sub rollback { $_[0]->{AutoCommit}=1; 1 }
    package ToggleTemplate;
    sub param { my ($s,%p)=@_; $s->{params}=\%p; }
    sub output { '' }
    package TogglePlugin;
    our @ISA=('Koha::Plugin::Com::Library::MediaManager');
    our @audit;
    sub _db { $_[0]->{db} ||= bless {AutoCommit=>1},'ToggleDB' }
    sub get_template { $_[0]->{template} = bless {},'ToggleTemplate' }
    sub output_html { 1 }
    sub _audit { push @audit,$_[1]; 1 }
    sub _error { $_[0]->{error}=$_[3]; return; }
}
my $t=TogglePlugin->new({cgi=>CGI->new});
$t->{data}={%cfg,protocol=>'code-v2',client_secret_hash=>secret_hash('a' x 64)};
{
    local %CGI::params=(%cfg,insecure_http=>1);
    $t->configure;
    is($t->{error},403,'non-superlibrarian cannot enable test mode');
    ok(!$t->_insecure_http,'still disabled');
}
{
    local $Koha::Patrons::patron->{flags}=1;
    local %CGI::params=(%cfg,insecure_http=>1);
    {
        local $Koha::Token::valid=0;
        delete $t->{error};
        $t->configure;
        is($t->{error},403,'CSRF required to enable test mode');
        ok(!$t->_insecure_http,'still disabled after CSRF failure');
    }
    {
        local $CGI::params{insecure_http}='';
        delete $t->{error};
        $t->configure;
        ok(!$t->{template}{params}{saved},'HTTP save without the checkbox is refused');
        ok(!$t->_insecure_http,'still disabled without the checkbox');
    }
    delete $t->{error};
    $t->configure;
    ok(!$t->{error} && $t->{template}{params}{saved},'superlibrarian saves with "Allow HTTP" over plain HTTP');
    is($t->retrieve_data('insecure_http'),'1','stored in plugin data');
    ok($t->_insecure_http && $t->_transport_ok,'HTTP accepted after enabling');
    ok($t->_ready,'HTTP application URL valid after enabling');
    is($t->{template}{params}{insecure_http},1,'checkbox shown ticked');
    is($TogglePlugin::audit[-1],'insecure_http_enabled','enabling is audited');

    {
        no warnings qw(redefine once);
        local *Koha::Plugin::Com::Library::MediaManager::new=sub { $t };
        local *Koha::Plugin::Com::Library::MediaManager::exchange=sub { (401,{error=>'invalid_client'}) };
        my $h=bless {},'HttpController';
        Koha::Plugin::Com::Library::MediaManager::Controller::exchange($h);
        is($h->{rendered}{status},401,'exchange honours the Configure-page setting');
    }

    # Unticking over HTTPS turns it off again.
    local $ENV{HTTPS}='on';
    local $CGI::params{insecure_http}='';
    local $CGI::params{mam_url}='https://dam.example.org';
    $t->configure;
    is($t->retrieve_data('insecure_http'),'0','unticked checkbox stores off');
    local $ENV{HTTPS}='off';
    ok(!$t->_transport_ok,'HTTP refused again after disabling');
    is($TogglePlugin::audit[-1],'insecure_http_disabled','disabling is audited');
}
done_testing;
