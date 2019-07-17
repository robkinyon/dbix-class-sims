# vi:sw=2
use strictures 2;

use Test::More;
use Test::Deep;

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
        name => {
          data_type => 'varchar',
          size => 128,
          is_nullable => 0,
        },
        hat_color => {
          data_type => 'varchar',
          size => 128,
          is_nullable => 1,
        },
      },
      primary_keys => [ 'id' ],
      unique_constraints => [
        [ 'name' ],
      ],
    },
  ]);
}

use common qw(sims_test Schema);

subtest "Load and retrieve a row by single-column PK" => sub {
  sims_test "Create the row" => {
    spec => {
      Artist => {
        name => 'Bob',
        hat_color => 'purple',
      },
    },
    expect => {
      Artist => { id => 1, name => 'Bob', hat_color => 'purple' },
    },
    addl => {
      duplicates => {},
    },
  };

  sims_test "Find the row" => {
    deploy => 0,
    loaded => {
      Artist => 1,
    },
    spec => [
      { Artist => { id => 1 } },
      { allow_pk_set_value => 1 },
    ],
    expect => {
      Artist => { id => 1, name => 'Bob', hat_color => 'purple' },
    },
    addl => {
      duplicates => {
        Artist => [{
          criteria => {
            id => 1,
          },
          found => ignore()
        }],
      },
    },
  };
};

subtest "Load and retrieve a row by single-column UK" => sub {
  sims_test "Create the row" => {
    spec => {
      Artist => {
        name => 'Bob',
        hat_color => 'purple',
      },
    },
    expect => {
      Artist => { id => 1, name => 'Bob', hat_color => 'purple' },
    },
    addl => {
      duplicates => {},
    },
  };

  sims_test "Find the row" => {
    deploy => 0,
    loaded => {
      Artist => 1,
    },
    spec => [
      { Artist => { name => 'Bob' } },
    ],
    expect => {
      Artist => { id => 1, name => 'Bob', hat_color => 'purple' },
    },
    addl => {
      duplicates => {
        Artist => [{
          criteria => {
            name => 'Bob',
          },
          found => ignore()
        }],
      },
    },
  };
};

subtest "Fail because a spec matches different rows in each UK" => sub {
  ok 1;
};

done_testing

