# vi:sw=2
use strictures 2;

use Test::More;
use Test::Deep; # Needed for re() below

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
      },
      primary_keys => [ 'id' ],
      has_many => {
        albums => { Album => 'artist_id' },
      },
    },
    Album => {
      columns => {
        id => {
          data_type => 'int',
          is_nullable => 0,
          is_auto_increment => 1,
        },
        artist_id => {
          data_type => 'int',
          is_nullable => 0,
        },
        name => {
          data_type => 'varchar',
          size => 128,
          is_nullable => 0,
        },
      },
      primary_keys => [ 'id' ],
      belongs_to => {
        artist => { Artist => 'artist_id' },
      },
    },
  ]);
}

use common qw(sims_test);

sims_test "Connect to a random parent" => {
  spec => {
    Artist => { name => 'foo' },
    Album => { name => 'bar' },
  },
  expect => {
    Artist => [ { id => 1, name => 'foo' } ],
    Album => [ { id => 1, name => 'bar', artist_id => 1 } ],
  },
};

sims_test "Connect parent/child by lookup" => {
  spec => {
    Artist => [ map { { name => "foo$_" } } 1..4 ],
    Album => [
      { name => 'bar1', 'artist.name' => 'foo3' },
      { name => 'bar2', 'artist.name' => 'foo1' },
    ],
  },
  expect => {
    Artist => [ map { { name => "foo$_" } } 1..4 ],
    Album  => [
      { id => 1, name => 'bar1', artist_id => 3 },
      { id => 2, name => 'bar2', artist_id => 1 },
    ],
  },
};

sims_test "Connect parent/child by object in relationship" => {
  load_sims => sub {
    my ($schema) = @_;
    my $rv = $schema->load_sims({
      Artist => [ map { { name => "foo$_" } } 1..4 ],
    });

    return $schema->load_sims({
      Album => { name => 'bar1', artist => $rv->{Artist}[2] },
    });
  },
  expect => {
    Artist => [ map { { id => $_, name => "foo$_" } } 1..4 ],
    Album  => [
      { id => 1, name => 'bar1', artist_id => 3 },
    ],
  },
  rv => sub { { Album => shift->{expect}{Album} } },
};

sims_test "Connect parent/child by object in column" => {
  load_sims => sub {
    my ($schema) = @_;
    my $rv = $schema->load_sims({
      Artist => [ map { { name => "foo$_" } } 1..4 ],
    });

    return $schema->load_sims({
      Album => { name => 'bar1', artist_id => $rv->{Artist}[2] },
    });
  },
  expect => {
    Artist => [ map { { id => $_, name => "foo$_" } } 1..4 ],
    Album  => [
      { id => 1, name => 'bar1', artist_id => 3 },
    ],
  },
  rv => sub { { Album => shift->{expect}{Album} } },
};

sims_test "Autogenerate a parent" => {
  spec => {
    Album => [
      { name => 'bar1' },
    ],
  },
  expect => {
    Artist => [
      { id => 1, name => re('.+') },
    ],
    Album  => [
      { id => 1, name => 'bar1', artist_id => 1 },
    ],
  },
  rv => sub { { Album => shift->{expect}{Album} } },
  addl => {
    created =>  {
      Artist => 1,
      Album => 1,
    },
  },
};

sims_test "Autogenerate a parent with a name" => {
  spec => {
    Album => [
      { name => 'bar1', 'artist.name' => 'foo3' },
      { name => 'bar2', 'artist.name' => 'foo1' },
    ],
  },
  expect => {
    Artist => [
      { id => 1, name => 'foo3' },
      { id => 2, name => 'foo1' },
    ],
    Album  => [
      { id => 1, name => 'bar1', artist_id => 1 },
      { id => 2, name => 'bar2', artist_id => 2 },
    ],
  },
  rv => sub { { Album => shift->{expect}{Album} } },
  addl => {
    created =>  {
      Artist => 2,
      Album => 2,
    },
  },
};

sims_test "Specify a parent and override a sims-spec" => {
  skip => 'Regressing until refactoring is done',
  spec => {
    Album => {
      artist => { name => { type => 'us_firstname' } },
      name => { type => 'us_lastname' },
    },
  },
  expect => {
    Album => [ { id => 1, name => re('.+'), artist_id => 1 } ],
  },
};

sims_test "Pick a random parent out of multiple choices" => {
  skip => 'Regressing until refactoring is done',
  spec => {
    Artist => [
      { name => 'foo' },
      { name => 'foo2' },
    ],
    Album => [
      { name => 'bar' },
    ],
  },
  expect => {
    Artist => [ { id => 1, name => 'foo' }, { id => 2, name => 'foo2' } ],
    Album  => [ { id => 1, name => 'bar', artist_id => re('1|2') } ],
  },
};

sims_test "Multiple rows connect to the same available parent" => {
  skip => 'Regressing until refactoring is done',
  spec => {
    Artist => [
      { name => 'foo' },
    ],
    Album => [
      { name => 'bar' },
      { name => 'baz' },
    ],
  },
  expect => {
    Artist => [ { id => 1, name => 'foo' } ],
    Album => [
      { id => 1, name => 'bar', artist_id => 1 },
      { id => 2, name => 'baz', artist_id => 1 },
    ],
  },
};

sims_test "Auto-generate a child with a value" => {
  skip => 'Regressing until refactoring is done',
  spec => {
    Artist => {
      name => 'foo',
      albums => [ { name => 'bar' } ],
    },
  },
  expect => {
    Artist => [ { id => 1, name => 'foo' } ],
    Album => [ { id => 1, name => 'bar', artist_id => 1 } ],
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Fail to generate a child due to a bad value" => {
  skip => 'Regressing until refactoring is done',
  spec => {
    Artist => {
      name => 'foo',
      albums => \'bad value',
    },
  },
  dies => qr/Don't know what to do with Artist->album/,
};

sims_test "Auto-generate a parent as necessary" => {
  skip => 'Regressing until refactoring is done',
  spec => {
    Album => {},
  },
  expect => {
    Artist => { id => 1, name => re('.+') },
    Album => { id => 1, name => re('.+'), artist_id => 1 },
  },
  rv => sub { { Album => shift->{expect}{Album} } },
};

sims_test "Force the creation of a parent" => {
  skip => 'Regressing until refactoring is done',
  spec => {
    Artist => [
      { name => 'foo' },
      { name => 'foo2' },
    ],
    Album => [
      { name => 'bar', artist => { __META__ => { create => 1 } } },
    ],
  },
  expect => {
    Artist => [
      { id => 1, name => 'foo' },
      { id => 2, name => 'foo2' },
      { id => 3, name => re('.+') },
    ],
    Album => { id => 1, name => 'bar', artist_id => 3 },
  },
  rv => {
    Artist => [
      { id => 1, name => 'foo' },
      { id => 2, name => 'foo2' },
    ],
    Album => [
      { id => 1, name => 'bar', artist_id => 3 },
    ],
  },
};

sims_test "Use a constraint to force a child row" => {
  skip => 'Regressing until refactoring is done',
  spec => [
    {
      Artist => {},
    },
    {
      constraints => {
        Artist => { albums => 1 },
      },
    },
  ],
  expect => {
    Artist => { id => 1, name => re('.+') },
    Album => { id => 1, name => re('.+'), artist_id => 1 },
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Use a constraint to force a child row (multiple parents)" => {
  skip => 'Regressing until refactoring is done',
  spec => [
    {
      Artist => 2,
    },
    {
      constraints => {
        Artist => { albums => 1 },
      },
    }
  ],
  expect => {
    Artist => [
      { id => 1, name => re('.+') },
      { id => 2, name => re('.+') },
    ],
    Album => [
      { id => 1, name => re('.+'), artist_id => 1 },
      { id => 2, name => re('.+'), artist_id => 2 },
    ],
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Use a constraint to force a child row (parent specific ID)" => {
  skip => 'Regressing until refactoring is done',
  spec => [
    {
      Artist => { id => 20 },
    },
    {
      constraints => {
        Artist => { albums => 1 },
      },
      allow_pk_set_value => 1,
    }
  ],
  expect => {
    Artist => { id => 20, name => re('.+') },
    Album => { id => 1, name => re('.+'), artist_id => 20 },
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Specify a child row and bypass the constraint" => {
  skip => 'Regressing until refactoring is done',
  spec => [
    {
      Artist => { albums => [ { name => 'ijkl' } ] },
    },
    {
      constraints => {
        Artist => { albums => 1 },
      },
    }
  ],
  expect => {
    Artist => { id => 1, name => re('.+') },
    Album => { id => 1, name => 'ijkl', artist_id => 1 },
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Autogenerate multiple children via constraint" => {
  skip => 'Regressing until refactoring is done',
  spec => [
    {
      Artist => {},
    },
    {
      constraints => {
        Artist => { albums => 2 },
      },
    },
  ],
  expect => {
    Artist => { id => 1, name => re('.+') },
    Album => [
      { id => 1, name => re('.+'), artist_id => 1 },
      { id => 2, name => re('.+'), artist_id => 1 },
    ],
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Specify various parent IDs and connect properly" => {
  skip => 'Regressing until refactoring is done',
  spec => [
    {
      Artist => [
        {
          id => 20, albums => [ { name => 'i20' }, { name => 'j20' } ],
        },
        {
          id => 10, albums => [ { name => 'i10' }, { name => 'j10' } ],
        },
      ],
    },
    {
      allow_pk_set_value => 1,
    },
  ],
  expect => {
    Artist => [
      { id => 20, name => re('.+') },
      { id => 10, name => re('.+') },
    ],
    Album => [
      { id => 1, name => 'i20', artist_id => 20 },
      { id => 2, name => 'j20', artist_id => 20 },
      { id => 3, name => 'i10', artist_id => 10 },
      { id => 4, name => 'j10', artist_id => 10 },
    ],
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Only create one child even if specified two ways" => {
  skip => 'Regressing until refactoring is done',
  spec => {
    Artist => { albums => [ { name => 'Bob' } ] },
    Album => { name => 'Bob' },
  },
  expect => {
    Artist => { id => 1, name => re('.+') },
    Album => { id => 1, name => 'Bob', artist_id => 1 },
  },
};

sims_test "Accept a number of children (1)" => {
  skip => 'Regressing until refactoring is done',
  spec => {
    Artist => {
      name => 'foo', albums => 1,
    },
  },
  expect => {
    Artist => { id => 1, name => 'foo' },
    Album => { id => 1, name => re('.+'), artist_id => 1 },
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Accept a number of children (2)" => {
  skip => 'Regressing until refactoring is done',
  spec => {
    Artist => {
      name => 'foo', albums => 2,
    },
  },
  expect => {
    Artist => { id => 1, name => 'foo' },
    Album => [
      { id => 1, name => re('.+'), artist_id => 1 },
      { id => 2, name => re('.+'), artist_id => 1 },
    ],
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Accept a hashref for children" => {
  skip => 'Regressing until refactoring is done',
  spec => {
    Artist => {
      name => 'foo', albums => { name => 'foobar' },
    },
  },
  expect => {
    Artist => { id => 1, name => 'foo' },
    Album => { id => 1, name => 'foobar', artist_id => 1 },
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Connect to the parent by reference" => {
  skip => 'Regressing until refactoring is done',
  spec => {
    Artist => 3,
    Album  => {
      name => 'foo',
      artist => \"Artist[1]",
    },
  },
  expect => {
    Artist => [
      { id => 1, name => re('.+') },
      { id => 2, name => re('.+') },
      { id => 3, name => re('.+') },
    ],
    Album => { id => 1, name => 'foo', artist_id => 2 },
  },
};

sims_test "Connect to the right parent by reference" => {
  skip => 'Regressing until refactoring is done',
  spec => {
    Artist => [
      { name => 'first' },
      { name => 'second' },
      { name => 'third' },
    ],
    Album  => [
      { artist => \"Artist[1]" },
      { artist => \"Artist[2]" },
      { artist => \"Artist[0]" },
    ],
  },
  expect => {
    Artist => [
      { id => 1, name => 'first' },
      { id => 2, name => 'second' },
      { id => 3, name => 'third' },
    ],
    Album => [
      { id => 1, name => re('.+'), artist_id => 2 },
      { id => 2, name => re('.+'), artist_id => 3 },
      { id => 3, name => re('.+'), artist_id => 1 },
    ],
  },
};

sims_test "Connect to the parent by reference" => {
  skip => 'Regressing until refactoring is done',
  spec => {
    Artist => { name => 'foo' },
    Album  => { name => \'Artist[0].name', artist => \'Artist[0]' },
  },
  expect => {
    Artist => [
      { id => 1, name => 'foo' },
    ],
    Album => { id => 1, name => 'foo', artist_id => 1 },
  },
};

# These tests verify the allow_relationship_column_name parameter
sims_test "Can use column name" => {
  skip => 'Regressing until refactoring is done',
  spec => {
    Artist => { name => 'bar' },
    Album => {
      name => 'foo',
      artist_id => 1,
    },
  },
  expect => {
    Artist => { id => 1, name => 'bar' },
    Album => { id => 1, name => 'foo', artist_id => 1 },
  },
};

sims_test "Cannot use column name" => {
  spec => [
    {
      Artist => { name => 'bar' },
      Album => {
        name => 'foo',
        artist_id => 1,
      },
    },
    { allow_relationship_column_names => 0 },
  ],
  dies => qr/DBIx::Class::Sims::Runner::run\(\): Cannot use column artist_id - use relationship artist/s,
};

done_testing;
