# vi:sw=2
use strictures 2;

use Test2::V0 qw( done_testing );

use lib 't/lib';

BEGIN {
  use loader qw(build_schema);
  build_schema([
    Artist => {
      columns => {
        id => {
          data_type => 'int',
          is_nullable => 0,
          is_auto_increment => 1,
        },
      },
      primary_keys => [ 'id' ],
    },
  ]);
}

use common qw(sims_test Schema);

sims_test "Table doesn't exist (strict off)" => {
  spec => [
    { NotThere => 1 },
    { ignore_unknown_tables => 1 },
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

sims_test "Column doesn't exist (strict off)" => {
  spec => [
    { Artist => { whatever => 1 } },
    { ignore_unknown_columns => 1 },
  ],
  expect => {
    Artist => { id => 1 },
  },
};

sims_test "Column doesn't exist (strict mode)" => {
  spec => [
    { Artist => { whatever => 1 } },
  ],
  dies => qr/DBIx::Class::Sims::Runner::run\(\): The following names are in the spec, but not the table Artist.whatever./s,
};

sims_test "Columns don't exist (strict mode) - shows sorting" => {
  spec => [
    { Artist => { whatever => 1, other_whatever => 1 } },
  ],
  dies => qr/DBIx::Class::Sims::Runner::run\(\): The following names are in the spec, but not the table Artist.other_whatever,whatever./s,
};

done_testing;
