# vi:sw=2
use strictures 2;

use Test::More;
use Test::Deep;

use_ok 'DBIx::Class::Sims';

cmp_bag(
  [ DBIx::Class::Sims->sim_types ],
  [qw(
    email_address ip_address
    us_firstname us_lastname us_name
    us_address us_city us_county us_phone us_ssntin us_state us_zipcode
  )],
  "List of types as expected",
);

done_testing;
