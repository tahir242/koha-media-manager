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
use Koha::Plugin::Com::Library::MediaManager::Controller;
{
    package MockController;
    sub res { $_[0] }
    sub req { $_[0] }
    sub headers { $_[0] }
    sub cache_control { $_[0]->{cache}=$_[1]; }
    sub header { $_[0]->{headers}{$_[1]}=$_[2] if @_>2; $_[0]->{headers}{$_[1]} }
    sub url { $_[0] }
    sub to_abs { $_[0] }
    sub scheme { $_[0]->{scheme} }
    sub body { $_[0]->{body} // '{}' }
    sub json { {code=>'c' x 64} }
    sub tx { $_[0] }
    sub remote_address { '192.0.2.1' }
    sub render { my ($s,%a)=@_; $s->{rendered}=\%a; }
}
my $c=bless {scheme=>'http'},'MockController';
Koha::Plugin::Com::Library::MediaManager::Controller::exchange($c);
is($c->{rendered}{status},400,'HTTP exchange refused');
is($c->{cache},'no-store','responses disable caches');
is($c->{headers}{'Referrer-Policy'},'no-referrer','referrer protected');
$c->{scheme}='https'; $c->{body}='x' x 1025;
Koha::Plugin::Com::Library::MediaManager::Controller::exchange($c);
is($c->{rendered}{status},413,'oversized body rejected');
$c->{body}='{}';
{
    no warnings 'redefine';
    local *Koha::Plugin::Com::Library::MediaManager::exchange=sub { return (429,{error=>'rate_limited'}) };
    Koha::Plugin::Com::Library::MediaManager::Controller::exchange($c);
    is($c->{rendered}{status},429,'exchange status preserved');
    is($c->{headers}{'Retry-After'},60,'retry header');
}
{
    no warnings 'redefine';
    local *Koha::Plugin::Com::Library::MediaManager::exchange=sub { die 'private database detail' };
    Koha::Plugin::Com::Library::MediaManager::Controller::exchange($c);
    is_deeply($c->{rendered},{status=>503,json=>{error=>'temporarily_unavailable'}},'storage exception sanitized');
}
done_testing;
