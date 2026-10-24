package MockKoha;
use strict;
use warnings;
# Isolated unit fixtures only. Never add t/lib to a production PERL5LIB.
BEGIN {
    $INC{$_} = __FILE__ for qw(Modern/Perl.pm C4/Context.pm C4/Auth.pm CGI.pm Koha/Plugins/Base.pm Koha/Biblios.pm Koha/Items.pm Koha/Patrons.pm Koha/Plugins/Methods.pm Koha/Plugins/Method.pm Koha/Token.pm Bytes/Random/Secure.pm);
}
package Modern::Perl;
sub import { strict->import; warnings->import; }
package C4::Context;
our $env = {number=>7,userid=>'staff',branch=>'MAIN'};
our $dbh;
our %config;
sub config { $config{$_[1]} }
sub userenv { $env }
sub dbh { $dbh }
package C4::Auth;
use Exporter 'import';
our @EXPORT_OK = qw(haspermission check_cookie_auth);
our %permissions = (catalogue=>1,tool=>1,edit_catalogue=>1);
our $status = 'ok';
our $session = bless {number=>7,interface=>'intranet'}, 'MockSession';
sub haspermission {
    my ($userid,$required) = @_;
    my ($key) = keys %$required;
    return $permissions{$required->{$key} eq '1' ? $key : $required->{$key}};
}
sub check_cookie_auth { return ($status,$session); }
package MockSession;
sub param { $_[0]->{$_[1]} }
package CGI;
our %params = (biblionumber=>123);
our $method = 'POST';
our $cookie = 'test-session';
sub new { bless {},shift }
sub param { $params{$_[1]} }
sub cookie { $cookie }
sub request_method { $method }
sub redirect { my ($self,%args)=@_; return $args{-uri}; }
package Koha::Plugins::Base;
sub new { bless $_[1],$_[0] }
sub retrieve_data { $_[0]->{data}{$_[1]} }
sub store_data { my ($s,$d)=@_; @{$s->{data}}{keys %$d}=values %$d; }
sub is_enabled { 1 }
sub get_qualified_table_name { 'mm_'.$_[1] }
sub mbf_path { 'Koha/Plugin/Com/Library/MediaManager/'.$_[1] }
package Koha::Biblios;
our $exists=1;
sub find { $exists ? bless({},'MockBiblio') : undef }
package Koha::Items;
# itemnumber => biblionumber; a missing key is a deleted item.
our %items=(456=>123);
sub find { exists $items{$_[1]} ? bless({itemnumber=>$_[1],biblionumber=>$items{$_[1]}},'MockItem') : undef }
package MockItem;
sub biblionumber { $_[0]->{biblionumber} }
package Koha::Plugins::Methods;
# Rows of plugin_methods as "class method".
our %rows;
sub search { my (undef,$w)=@_; return bless {n=>$rows{"$w->{plugin_class} $w->{plugin_method}"} ? 1 : 0},'MockResultSet'; }
package MockResultSet;
sub count { $_[0]->{n} }
package Koha::Plugins::Method;
sub new { bless $_[1],$_[0] }
sub store { $Koha::Plugins::Methods::rows{"$_[0]->{plugin_class} $_[0]->{plugin_method}"}=1; $_[0] }
package Koha::Patrons;
our $patron = bless {borrowernumber=>7,userid=>'staff',flags=>0}, 'MockPatron';
sub find { $patron }
package MockPatron;
sub borrowernumber { $_[0]->{borrowernumber} }
sub userid { $_[0]->{userid} }
sub flags { $_[0]->{flags} }
sub account_locked { $_[0]->{locked} // 0 }
sub is_expired { $_[0]->{expired} // 0 }
sub is_debarred { $_[0]->{debarred} // 0 }
sub lost { 0 }
sub gonenoaddress { 0 }
package Koha::Token;
our $valid=1;
sub new { bless {},shift }
sub generate_csrf { 'fixture-csrf' }
sub check_csrf { $valid }
package Bytes::Random::Secure;
sub new { bless {},shift }
sub bytes { return 'r' x $_[1] } # Deterministic fixture, not a randomness test.
package MockKoha;
1;
