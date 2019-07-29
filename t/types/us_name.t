# vi:sw=2
use strictures 2;

use Test2::V0 qw( done_testing like );

my $sub = DBIx::Class::Sims::Types->can('us_name');

my $info = {
  data_type => 'varchar',
  sim => { type => 'us_name' },
};
my $expected = qr/^\w+ (?:\w\. )?[\w']+(?: \w+)?(?: .+)?$/;
for ( 1 .. 1000 ) {
  like( $sub->($info), $expected );
}

done_testing;
