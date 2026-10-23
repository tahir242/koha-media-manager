use strict;
use warnings;
use Test::More;
use lib '.', 't/lib';
use MockKoha;
use Koha::Plugin::Com::Library::MediaManager;
{
    package ErrorPlugin;
    our @ISA=('Koha::Plugin::Com::Library::MediaManager');
    sub _error { push @{$_[0]->{errors}},$_[3]; return; }
    sub _dashboard { $_[0]->{dashboard}++ }
}
my $p=ErrorPlugin->new({cgi=>CGI->new});
$p->{data}={};
{
    local $CGI::params{op}='';
    $p->tool;
    is_deeply($p->{errors},[403],'non-administrator sees exactly one error page (no extra 503)');
}
{
    local $Koha::Patrons::patron->{flags}=1;
    local $Koha::Token::valid=0;
    local $CGI::params{op}='cud-test';
    $p->{errors}=[];
    $p->tool;
    is_deeply($p->{errors},[403],'CSRF failure renders exactly one error page');
    ok(!$p->{dashboard},'dashboard not rendered after CSRF failure');
}
done_testing;
