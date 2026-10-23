use strict;
use warnings;
use Test::More;
use lib '.', 't/lib';
use MockKoha;
use Koha::Plugin::Com::Library::MediaManager;
{
    package DashDB;
    our $total=45;
    our @limit;
    sub selectrow_array { return ($total) }
    sub selectall_arrayref {
        my ($s,$sql,$attr,@bind)=@_;
        @limit=@bind[-2,-1];
        my ($per,$offset)=@limit;
        my $n=$total-$offset < $per ? $total-$offset : $per;
        return [map { {id=>$total-$offset-$_,event_epoch=>0} } 0..$n-1];
    }
    package DashTemplate;
    sub param { my ($s,%p)=@_; $s->{params}=\%p; }
    sub output { '' }
    package DashPlugin;
    our @ISA=('Koha::Plugin::Com::Library::MediaManager');
    sub _db { bless {},'DashDB' }
    sub get_template { $_[0]->{template}=bless {},'DashTemplate' }
    sub output_html { 1 }
}
my $p=DashPlugin->new({cgi=>CGI->new});
$p->{data}={mam_url=>'https://dam.example.org'};
sub page { local $CGI::params{page}=$_[0]; $p->_dashboard(CGI->new); return $p->{template}{params}; }

my $v=page(1);
is($v->{total},45,'total events counted');
is($v->{pages},3,'20 per page gives 3 pages');
is_deeply([@DashDB::limit],[20,0],'first page query: LIMIT 20 OFFSET 0');
is_deeply($v->{page_numbers},[1,2,3],'page numbers listed');
is($v->{first_row},1,'showing from 1');
is($v->{last_row},20,'showing to 20');
is($v->{next},2,'next page');
is($v->{previous},0,'no previous page');
like($v->{page_base},qr{class=Koha%3A%3APlugin%3A%3ACom%3A%3ALibrary%3A%3AMediaManager&method=tool&event=&page=$},'page links keep class and filter');

$v=page(3);
is_deeply([@DashDB::limit],[20,40],'last page query: OFFSET 40');
is($v->{first_row},41,'last page starts at 41');
is($v->{last_row},45,'last page ends at 45');
is($v->{next},0,'no next page on last page');

$v=page(99);
is($v->{page},3,'out-of-range page clamps to last');
{
    local $DashDB::total=0;
    $v=page(1);
    is($v->{pages},1,'empty log has one page');
    is($v->{first_row},0,'nothing shown');
}
{
    local $DashDB::total=500;
    $v=page(10);
    is_deeply($v->{page_numbers},[8,9,10,11,12],'window of five page numbers around current page');
}
done_testing;
