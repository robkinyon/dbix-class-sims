# vi:sw=2
use strict;
use warnings FATAL => 'all';

use Test::More;

use_ok 'DBIx::Class::Sims::Types';

my $sub = DBIx::Class::Sims::Types->can('us_address');

my @tests = (
  [ { data_type => 'varchar' }, qr/^\d{1,5} \w+ [\w.]+$/ ],
);

foreach my $test ( @tests ) {
  $test->[0]{sim} = { type => 'us_address' };
  like( $sub->($test->[0]), $test->[1] );
}

done_testing;
