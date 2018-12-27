# vi:sw=2
use strictures 2;

use Test::More;
use Test::Deep;

use lib 't/lib';

BEGIN {
  use loader qw(build_schema);
  build_schema([
    Artist => {
      table => 'artists',
      columns => {
        id => {
          data_type => 'int',
          is_nullable => 0,
          is_auto_increment => 1,
        },
        name => {
          data_type => 'varchar',
          size => 128,
          is_nullable => 0,
        },
        hat_color => {
          data_type => 'varchar',
          size => 128,
          is_nullable => 1,
          sim => { value => 'purple' },
        },
      },
      primary_keys => [ 'id' ],
    },
  ]);
}

use common qw(sims_test Schema);

sims_test "Table doesn't exist" => {
  spec => [
    { NotThere => 1 },
    { strict_mode => 0 },
  ],
  expect => {
  },
};

sims_test "Table doesn't exist (strict mode)" => {
  spec => { NotThere => 1 },
  dies => qr/DBIx::Class::Sims::Runner::run\(\): The following names are in the spec, but not the schema:.NotThere./s,
};

sims_test "Tables don't exist (strict mode) - shows sorting" => {
  spec => { NotThere => 1, AlsoNotThere => 1 },
  dies => qr/DBIx::Class::Sims::Runner::run\(\): The following names are in the spec, but not the schema:.AlsoNotThere,NotThere./s,
};

done_testing;
