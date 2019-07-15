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
        city => {
          data_type => 'varchar',
          size => 128,
          is_nullable => 0,
        },
        state => {
          data_type => 'varchar',
          size => 128,
          is_nullable => 0,
        },
      },
      primary_keys => [ 'id' ],
      unique_constraints => [
        [ 'name' ],
        [ 'city', 'state' ],
      ],
    },
  ]);
}

use common qw(sims_test Schema);

subtest "Load and retrieve a row by single-column PK" => sub {
  sims_test "Create the row" => {
    skip => 'still building',
    spec => {
      Artist => {
        name => 'Bob',
        city => 'Some',
        state => 'Place',
      },
    },
    expect => {
      Artist => { id => 1, name => 'Bob', city => 'Some', state => 'Place' },
    },
    addl => {
      duplicates => {},
    },
  };

  sims_test "Find the row" => {
    skip => 'still building',
    deploy => 0,
    loaded => {
      Artist => 1,
    },
    spec => [
      { Artist => { id => 1 } },
      { allow_pk_set_value => 1 },
    ],
    expect => {
      Artist => { id => 1, name => 'Bob', city => 'Some', state => 'Place' },
    },
    addl => {
      #duplicates => {
      #  Artist => [{
      #    criteria => {
      #      id => 1,
      #    },
      #    found => ignore()
      #  }],
      #},
    },
  };
};

subtest "Load and retrieve a row by single-column UK" => sub {
  my $spec = {
    Artist => { name => 'Taylor Swift' },
  };

  sims_test "Create the row" => {
    skip => 'Regressing until refactoring is done',
    spec => $spec,
    expect => {
      Artist => { id => 1, name => 'Taylor Swift', city => re('.+'), state => re('.+') },
    },
    addl => {
      duplicates => {},
    },
  };

  sims_test "Find the row" => {
    skip => 'Regressing until refactoring is done',
    deploy => 0,
    loaded => {
      Artist => 1,
    },
    spec => $spec,
    expect => {
      Artist => { id => 1, name => 'Taylor Swift', city => re('.+'), state => re('.+') },
    },
    addl => {
      duplicates => {
        Artist => [{
          criteria => {
            name => 'Taylor Swift',
          },
          found => ignore()
        }],
      },
    },
  };
};

subtest "Load and retrieve a row by multi-col UK" => sub {
  my $spec = {
    Artist => { first_name => 'Taylor', last_name => 'Swift' },
  };

  sims_test "Create the row" => {
    skip => 'Regressing until refactoring is done',
    spec => $spec,
    expect => {
      Artist => { id => 1, first_name => 'Taylor', last_name => 'Swift' },
    },
    addl => {
      duplicates => {},
    },
  };

  sims_test "Find the row" => {
    skip => 'Regressing until refactoring is done',
    deploy => 0,
    loaded => {
      Artist => 1,
    },
    spec => $spec,
    expect => {
      Artist => { id => 1, first_name => 'Taylor', last_name => 'Swift' },
    },
    addl => {
      duplicates => {
        Artist => [{
          criteria => {
            first_name => 'Taylor',
            last_name => 'Swift',
          },
          found => ignore()
        }],
      },
    },
  };
};

subtest "Don't specify enough to find by multi-col UK" => sub {
  sims_test "Create the row" => {
    skip => 'Regressing until refactoring is done',
    spec => {
      Artist => { first_name => 'Taylor', last_name => 'Swift' },
    },
    expect => {
      Artist => { id => 1, first_name => 'Taylor', last_name => 'Swift' },
    },
  };

  sims_test "Throw an error finding the row" => {
    skip => 'Regressing until refactoring is done',
    deploy => 0,
    loaded => {
      Artist => 1,
    },
    spec => {
      Artist => { first_name => 'Taylor2', last_name => 'Swift' },
    },
    dies => qr/UNIQUE constraint failed/,
  };
};

subtest "Load and retrieve a row by other UK" => sub {
  sims_test "Create the row" => {
    skip => 'Regressing until refactoring is done',
    spec => {
      Artist => { first_name => 'Taylor', last_name => 'Swift' },
    },
    expect => {
      Artist => { id => 1, first_name => 'Taylor', last_name => 'Swift' },
    },
  };

  sims_test "Find the row" => {
    skip => 'Regressing until refactoring is done',
    deploy => 0,
    loaded => {
      Artist => 1,
    },
    spec => {
      Artist => { last_name => 'Swift' },
    },
    expect => {
      Artist => { id => 1, first_name => 'Taylor', last_name => 'Swift' },
    },
  };
};

done_testing
