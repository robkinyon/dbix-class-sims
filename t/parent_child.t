# vi:sw=2
use strictures 2;

use Test::More;
use Test::Deep; # Needed for re() below

BEGIN {
  use t::loader qw(build_schema);
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
      },
      primary_keys => [ 'id' ],
      has_many => {
        albums => { Album => 'artist_id' },
      },
    },
    Album => {
      table => 'albums',
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

use t::common qw(sims_test);

sims_test "Connect parent/child by id" => {
  spec => {
    Artist => [ { id => 1, name => 'foo' } ],
    Album => [ { name => 'bar', artist_id => 1 } ],
  },
  expect => sub { shift->{spec} },
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

sims_test "Pick a random parent out of multiple choices" => {
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

sims_test "Auto-generate a parent as necessary" => {
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

done_testing;
__END__

subtest "Use a constraint to force a child row (parent specific ID)" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => [
          { id => 20 },
        ],
      },
      {
        constraints => {
          Artist => { albums => 1 },
        },
      }
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 20, 'abcd' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'efgh', 20 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 20) ],
  });
};

subtest "Specify a child row and bypass the constraint" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => [
          { albums => [ { name => 'ijkl' } ] },
        ],
      },
      {
        constraints => {
          Artist => { albums => 1 },
        },
      }
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'abcd' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'ijkl', 1 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1) ],
  });
};

subtest "Specify many child rows and bypass the constraint" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => [
          {
            id => 10,
            albums => [ { name => 'ijkl' }, { name => 'mnop' } ],
          },
        ],
      },
      {
        constraints => {
          Artist => { albums => 1 },
        },
      }
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 10, 'abcd' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'ijkl', 10 ],
    [ 2, 'mnop', 10 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 10) ],
  });
};

subtest "Specify various parent IDs and connect properly" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => [
          {
            id => 20,
            albums => [ { name => 'i20' }, { name => 'j20' } ],
          },
          {
            id => 10,
            albums => [ { name => 'i10' }, { name => 'j10' } ],
          },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 10, 'abcd' ],
    [ 20, 'abcd' ],
  ], "Artist fields are right";
  # Are these IDs in any specific order?
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'i20', 20 ],
    [ 2, 'j20', 20 ],
    [ 3, 'i10', 10 ],
    [ 4, 'j10', 10 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 20), methods(id => 10) ],
  });
};

subtest "Autogenerate multiple children via constraint" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => [
          {},
        ],
      },
      {
        constraints => {
          Artist => { albums => 2 },
        },
      }
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'abcd' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'efgh', 1 ],
    [ 2, 'efgh', 1 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1) ],
  });
};

subtest "Only create one child even if specified two ways" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => [
          { albums => [ { name => 'Bob' } ] },
        ],
        Album => [
          { name => 'Bob' },
        ],
      }
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'abcd' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'Bob', 1 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1) ],
    Album  => [ methods(id => 1, name => 'Bob') ],
  });
};

subtest "Accept a number of children (1)" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => [
          {
            name => 'foo',
            albums => 1,
          },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'foo' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'efgh', 1 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1) ],
  });
};

subtest "Accept a number of children (2)" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => [
          {
            name => 'foo',
            albums => 2,
          },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'foo' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'efgh', 1 ],
    [ 2, 'efgh', 1 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1) ],
  });
};

subtest "Accept a hashref for children" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => [
          {
            name => 'foo',
            albums => { name => 'foobar' },
          },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'foo' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'foobar', 1 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1) ],
  });
};

subtest "Connect to the parent by reference" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => 1,
        Album  => {
          name => 'foo',
          artist => \"Artist[0]",
        },
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'abcd' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'foo', 1 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1) ],
    Album  => [ methods(id => 1) ],
  });
};

subtest "Connect to the right parent by reference" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
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
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'first' ],
    [ 2, 'second' ],
    [ 3, 'third' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'efgh', 2 ],
    [ 2, 'efgh', 3 ],
    [ 3, 'efgh', 1 ],
  ], "Album fields are right";
};

done_testing;
