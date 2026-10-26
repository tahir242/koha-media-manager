use strict;
use warnings;
use Test::More;
use lib '.', 't/lib';
use MockKoha;
use Koha::Plugin::Com::Library::MediaManager;

my $plugin=Koha::Plugin::Com::Library::MediaManager->new({});
my %params=$plugin->_form_params(CGI->new);
is($params{sessionID},'test-session','native template CSRF generator receives staff session');
is($params{mm_csrf_token},'fixture-csrf','older Koha receives a nonempty fallback');
{
    local $CGI::cookie='';
    eval { $plugin->_form_params(CGI->new) };
    like($@,qr/Staff session required/,'missing session cannot render a tokenless form');
}
{
    no warnings 'redefine';
    local *Koha::Token::generate_csrf=sub { return undef };
    eval { $plugin->_form_params(CGI->new) };
    like($@,qr/Could not generate/,'token generation failure cannot render an empty field');
}
{
    no warnings 'redefine';
    local *Koha::Token::check_csrf=sub {
        my ($self,$args)=@_;
        return $args->{session_id} eq 'test-session' && ($args->{token} // '') eq 'fixture-csrf';
    };
    local $CGI::params{csrf_token}='fixture-csrf';
    ok($plugin->_valid_post(CGI->new),'submitted token is validated against the same session');
    $CGI::params{csrf_token}='';
    ok(!$plugin->_valid_post(CGI->new),'missing submitted token remains rejected');
}

for my $file (qw(configure.tt tool.tt continue.tt)) {
    open my $fh,'<',"Koha/Plugin/Com/Library/MediaManager/$file" or die $!;
    local $/;
    my $source=<$fh>;
    like($source,qr/SET mm_form_csrf = Koha\.GenerateCSRF \|\| mm_csrf_token/,
        "$file uses the native token with the older-release fallback");
    my @forms=$source =~ m{(<form\b[^>]*method="post"[\s\S]*?</form>)}g;
    ok(scalar @forms >= 1,"$file has POST forms");
    for my $form (@forms) {
        like($form,qr/name="csrf_token" value="\[% mm_form_csrf \| html %\]"/,
            "$file submits its CSRF token within every POST form");
        like($form,qr/name="op" value="cud-/,"$file preserves Koha's mutation convention");
    }
}
{
    open my $fh,'<','Koha/Plugin/Com/Library/MediaManager/tool.tt' or die $!;
    local $/;
    my ($form)=<$fh> =~ m{(<form\b[^>]*>(?:(?!</form>)[\s\S])*name="scope" value="dashboard"[\s\S]*?</form>)};
    ok($form,'"Go to MAM" is a sign-in form, not a plain link');
    like($form,qr/target="_blank"/,'"Go to MAM" opens in a new tab');
    like($form,qr/name="op" value="cud-authorize"/,'"Go to MAM" starts the regular sign-in');
}
done_testing;
