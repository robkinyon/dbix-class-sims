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
    spec => { Artist => { name => 'Bob' } },
    expect => {
      Artist => { id => 1, name => 'Bob', city => re('.+'), state => re('.+') },
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
    spec => { Artist => { name => 'Bob' } },
    expect => {
      Artist => { id => 1, name => 'Bob', city => re('.+'), state => re('.+') },
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

subtest "Load and retrieve a row by multi-col UK" => sub {
  sims_test "Create the row" => {
    spec => { Artist => { city => 'AB', state => 'CD' } },
    expect => {
      Artist => { id => 1, name => re('.+'), city => 'AB', state => 'CD' },
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
    spec => { Artist => { city => 'AB', state => 'CD' } },
    expect => {
      Artist => { id => 1, name => re('.+'), city => 'AB', state => 'CD' },
    },
    addl => {
      duplicates => {
        Artist => [{
          criteria => {
            city => 'AB',
            state => 'CD',
          },
          found => ignore()
        }],
      },
    },
  };
};

# Force the columns in the other UK to be set predictably
Schema->source('Artist')->column_info('city')->{sim}{value} = 'AB';
Schema->source('Artist')->column_info('state')->{sim}{value} = 'CD';

subtest "Load, then retrieve a row by other UK" => sub {
  sims_test "Create the row" => {
    spec => {
      Artist => { name => 'Bob' },
    },
    expect => {
      Artist => { id => 1, name => 'Bob', city => 'AB', state => 'CD' },
    },
  };

  sims_test "Find the row" => {
    deploy => 0,
    loaded => {
      Artist => 1,
    },
    spec => {
      Artist => { city => 'AB', state => 'CD' },
    },
    expect => {
      Artist => { id => 1, name => 'Bob', city => 'AB', state => 'CD' },
    },
    addl => {
      duplicates => {
        Artist => [{
          criteria => {
            city => 'AB',
            state => 'CD',
          },
          found => ignore()
        }],
      },
    },
  };
};

done_testing
