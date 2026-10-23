use strict;
use warnings;
use Test::More;
use lib '.', 't/lib';
use MockKoha;
use Koha::Plugin::Com::Library::MediaManager;
use Koha::Plugin::Com::Library::MediaManager::Security qw(secret_hash);
{
    package ConfigDB;
    sub begin_work { $_[0]->{AutoCommit}=0; 1 }
    sub selectrow_array { 1000 }
    sub commit { $_[0]->{AutoCommit}=1; 1 }
    sub rollback { $_[0]->{AutoCommit}=1; 1 }
    package ConfigTemplate;
    sub param { my ($s,%p)=@_; $s->{params}=\%p; }
    sub output { JSON::PP::encode_json($_[0]->{params}) }
    package ConfigPlugin;
    our @ISA=('Koha::Plugin::Com::Library::MediaManager');
    sub _db { $_[0]->{db} ||= bless {AutoCommit=>1},'ConfigDB' }
    sub get_template { bless {},'ConfigTemplate' }
    sub output_html { $_[0]->{output}=$_[1]; }
    sub _audit { 1 }
    sub _error { $_[0]->{error}=$_[3]; return; }
}
my $p=ConfigPlugin->new({cgi=>CGI->new});
$p->{data}={mam_url=>'https://dam.example.org',instance_id=>'library',client_id=>'dam',
    code_ttl=>60,rotation_grace=>300,audit_retention=>90,button_label=>'Upload',staff_policy=>'cataloguers',
    health_ips=>'',protocol=>'code-v2',client_secret_hash=>secret_hash('a' x 64)};
local $Koha::Patrons::patron->{flags}=1;
local $ENV{HTTPS}='on';
local %CGI::params=%{$p->_config};
$p->configure;
is($p->retrieve_data('client_secret_hash'),secret_hash('a' x 64),'blank input preserves secret');
unlike($p->{output},qr/@{[secret_hash('a' x 64)]}/,'stored digest never rendered');
$CGI::params{client_secret}='b' x 64;
$p->configure;
is($p->retrieve_data('client_secret_hash'),secret_hash('b' x 64),'new secret hashed');
is($p->retrieve_data('previous_secret_hash'),secret_hash('a' x 64),'old digest retained for overlap');
is($p->retrieve_data('previous_secret_until'),1300,'rotation expiration uses database time');
unlike($p->{output},qr/@{['b' x 64]}/,'replacement secret never reflected');
$CGI::params{mam_url}='javascript:alert(1)';
$p->configure;
is($p->retrieve_data('mam_url'),'https://dam.example.org','unsafe URL never saved');
{
    local $Koha::Token::valid=0;
    $p->configure;
    is($p->{error},403,'CSRF rejection');
}
{
    local $Koha::Patrons::patron->{flags}=0;
    $p->configure;
    is($p->{error},403,'non-admin cannot configure');
}
{
    # Saving over plain HTTP without ticking "Allow HTTP" is refused with a form error.
    local $ENV{HTTPS}='off';
    local $CGI::params{client_secret}='c' x 64;
    delete $p->{error};
    $p->configure;
    my $view=JSON::PP::decode_json($p->{output});
    ok(!$view->{saved},'HTTP save without "Allow HTTP" is not saved');
    like(join(' ',@{$view->{errors}}),qr/Allow HTTP/,'error explains the Allow HTTP checkbox');
    is($p->retrieve_data('client_secret_hash'),secret_hash('b' x 64),'secret unchanged');
}
{
    local $ENV{HTTPS}='off';
    local $CGI::method='GET';
    delete $p->{error};
    $p->configure;
    ok(!exists $p->{error},'HTTP configuration GET renders the form');
    my $view=JSON::PP::decode_json($p->{output});
    is($view->{mam_url},'https://dam.example.org','existing settings remain visible');
    ok(!exists $view->{client_secret_hash},'view contains no credential digest');
}
done_testing;
