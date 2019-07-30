# vi:sw=2
use strictures 2;

use Test2::V0 qw( done_testing );

use lib 't/lib';

BEGIN {
  use loader qw(build_schema);
  build_schema([
    Country => {
      columns => {
        code => {
          data_type   => 'char',
          size        => 2,
          is_nullable => 0,
          sim => { value => 'US' },
        },
      },
      primary_keys => [ 'code' ],
    },
  ]);
}

use common qw(sims_test);

sims_test "Can use a default value for a char PK" => {
  spec => {
    Country => {},
  },
  expect => {
    Country => { code => 'US' },
  },
};

sims_test "Can set the value for a char PK" => {
  spec => {
    Country => { code => 'UK' },
  },
  expect => {
    Country => { code => 'UK' },
  },
};

done_testing;
