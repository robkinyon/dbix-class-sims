# vi:sw=2
use strictures 2;

use Test2::V0 qw(
  done_testing subtest E match is
  array hash field item end
  ok
);

use lib 't/lib';

use File::Path qw( remove_tree );
use YAML::Any qw( LoadFile );

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
      { id => 1, name => E() },
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

# QUESTION: Do we want this test?
sims_test "Specify a parent and override a sims-spec" => {
  skip => 'Unclear if we even want this test or not',
  spec => {
    Album => {
      artist => { name => { type => 'us_firstname' } },
      name => { type => 'us_lastname' },
    },
  },
  expect => {
    Album => [ { id => 1, name => E(), artist_id => 1 } ],
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
    Album  => [ { id => 1, name => 'bar', artist_id => match(qr/1|2/) } ],
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
      { id => 3, name => E() },
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

sims_test "Fail to generate a child due to a bad value" => {
  spec => {
    Artist => {
      name => 'foo',
      albums => \'bad value',
    },
  },
  dies => qr/Unsure what to do about Artist->albums => bad value/,
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
    Artist => { id => 1, name => E() },
    Album => { id => 1, name => E(), artist_id => 1 },
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
      { id => 1, name => E() },
      { id => 2, name => E() },
    ],
    Album => [
      { id => 1, name => E(), artist_id => 1 },
      { id => 2, name => E(), artist_id => 2 },
    ],
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Use a constraint to force a child row (parent specific ID)" => {
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
    Artist => { id => 20, name => E() },
    Album => { id => 1, name => E(), artist_id => 20 },
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Specify a child row and bypass the constraint" => {
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
    Artist => { id => 1, name => E() },
    Album => { id => 1, name => 'ijkl', artist_id => 1 },
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Autogenerate multiple children via constraint" => {
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
    Artist => { id => 1, name => E() },
    Album => [
      { id => 1, name => E(), artist_id => 1 },
      { id => 2, name => E(), artist_id => 1 },
    ],
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Autogenerate one child via constraint because there's another already there" => {
  spec => [
    {
      Artist => { albums => [{ name => 'Bob' }] },
    },
    {
      constraints => {
        Artist => { albums => 2 },
      },
    },
  ],
  expect => {
    Artist => { id => 1, name => E() },
    Album => [
      { id => 1, name => 'Bob', artist_id => 1 },
      { id => 2, name => E(), artist_id => 1 },
    ],
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Autogenerate no child via constraint because enough are there" => {
  spec => [
    {
      Artist => { albums => [{ name => 'Bob' }, { name => 'Bob2' }] },
    },
    {
      constraints => {
        Artist => { albums => 2 },
      },
    },
  ],
  expect => {
    Artist => { id => 1, name => E() },
    Album => [
      { id => 1, name => 'Bob', artist_id => 1 },
      { id => 2, name => 'Bob2', artist_id => 1 },
    ],
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Specify various parent IDs and connect properly" => {
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
      { id => 20, name => E() },
      { id => 10, name => E() },
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
  spec => {
    Artist => { albums => [ { name => 'Bob' } ] },
    Album => { name => 'Bob' },
  },
  expect => {
    Artist => { id => 1, name => E() },
    Album => { id => 1, name => 'Bob', artist_id => 1 },
  },
};

sims_test "Accept a number of children (1)" => {
  spec => {
    Artist => {
      name => 'foo', albums => 1,
    },
  },
  expect => {
    Artist => { id => 1, name => 'foo' },
    Album => { id => 1, name => E(), artist_id => 1 },
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Accept a number of children (2)" => {
  spec => {
    Artist => {
      albums => 2,
    },
  },
  expect => {
    Artist => { id => 1, name => E() },
    Album => [
      { id => 1, name => E(), artist_id => 1 },
      { id => 2, name => E(), artist_id => 1 },
    ],
  },
  rv => sub { { Artist => shift->{expect}{Artist} } },
};

sims_test "Accept a hashref for children" => {
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

sims_test "Only create one child even if under-specified two ways" => {
  spec => {
    Artist => { name => 'Joe', albums => 1 },
    Album => { name => 'Bob', 'artist.name' => 'Joe' },
  },
  expect => {
    Artist => { id => 1, name => E() },
    Album => { id => 1, name => 'Bob', artist_id => 1 },
  },
};

sims_test "Create a second child even if the first is found" => {
  spec => {
    Artist => { name => 'Joe', albums => 2 },
    Album => { name => 'Bob', 'artist.name' => 'Joe' },
  },
  expect => {
    Artist => { id => 1, name => E() },
    Album => [
      { id => 1, name => 'Bob', artist_id => 1 },
      { id => 2, name => E(), artist_id => 1 },
    ],
  },
};

=pod
# It's not clear we actually want this. In fact, why would you do this?
sims_test "Fill in the unspecified child with the created child" => {
  spec => {
    Artist => { name => 'Joe', albums => [ {}, { name => 'Bob2' } ] },
    Album => { name => 'Bob', 'artist.name' => 'Joe' },
  },
  expect => {
    Artist => { id => 1, name => E() },
    Album => [
      { id => 1, name => 'Bob', artist_id => 1 },
      { id => 2, name => 'Bob2', artist_id => 1 },
    ],
  },
  rv => {
    Artist => { id => 1, name => 'Joe' },
    Album => [
      { id => 1, name => 'Bob', artist_id => 1 },
    ],
  },
};
=cut

sims_test "Create a child of a found parent" => {
  spec => {
    Artist => { name => 'Joe' },
    Album => {
      name => 'Bob',
      artist => {
        name => 'Joe',
        albums => [ { name => 'Charlie' } ],
      },
    },
  },
  expect => {
    Artist => { id => 1, name => E() },
    Album => [
      { id => 1, name => 'Bob', artist_id => 1 },
      { id => 2, name => 'Charlie', artist_id => 1 },
    ],
  },
  rv => {
    Artist => { id => 1, name => E() },
    Album => [
      { id => 1, name => 'Bob', artist_id => 1 },
    ],
  },
};

sims_test "Connect to the parent by reference" => {
  spec => {
    Artist => 3,
    Album  => {
      name => 'foo',
      artist => \"Artist[1]",
    },
  },
  expect => {
    Artist => [
      { id => 1, name => E() },
      { id => 2, name => E() },
      { id => 3, name => E() },
    ],
    Album => { id => 1, name => 'foo', artist_id => 2 },
  },
};

sims_test "Connect to the right parent by reference" => {
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
      { id => 1, name => E(), artist_id => 2 },
      { id => 2, name => E(), artist_id => 3 },
      { id => 3, name => E(), artist_id => 1 },
    ],
  },
};

sims_test "Use a parent's column by reference" => {
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

sims_test "Backreference as object" => {
  spec => {
    Album  => [
      { name => 'foo' },
      { name => 'bar', artist => \'Album[0].artist' },
    ],
  },
  expect => {
    Album => [
      { id => 1, name => 'foo', artist_id => 1 },
      { id => 2, name => 'bar', artist_id => 1 },
    ],
  },
};

# These tests verify the allow_relationship_column_name parameter
sims_test "Can use column name" => {
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
  dies => qr/DBIx::Class::Sims::Runner::.*\(\): Cannot use column artist_id - use relationship artist/s,
};

sims_test "Save object trace with an implicit parent" => {
  load_sims => sub {
    my ($schema) = @_;

    my $trace_file = '/tmp/trace';

    remove_tree( $trace_file );

    my @rv = $schema->load_sims(
      { Album => { name => 'bar1' } },
      { object_trace => $trace_file },
    );

    # Verify the trace was written out
    my $trace = LoadFile( $trace_file );
    my $check = hash {
      field objects => array {
        item hash {
          field parent => 0;
          field seen => 1;
          field table => 'Album';
          field spec => hash {
            field name => 'bar1';
            end;
          };
          field made => 2;
          field create_params => hash {
            field name => 'bar1';
            field artist_id => 1;
            end;
          };
          field row => hash {
            field id => 1;
            field name => 'bar1';
            field artist_id => 1;
            end;
          };
          end;
        };
        item hash {
          field parent => 1;
          field via => 'populate_parents/artist';
          field seen => 2;
          field table => 'Artist';
          field spec => hash {
            end;
          };
          field made => 1;
          field create_params => hash {
            field name => E;
            end;
          };
          field row => hash {
            field id => 1;
            field name => E;
            end;
          };
          end;
        };
        end;
      };
      end;
    };
    is( $trace, $check, 'Toposort trace is as expected' );

    remove_tree( $trace_file );

    return @rv;
  },
  expect => {
    Artist => [
      { id => 1, name => E() },
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

sims_test "Save object trace with a specified parent" => {
  load_sims => sub {
    my ($schema) = @_;

    my $trace_file = '/tmp/trace';

    remove_tree( $trace_file );

    my @rv = $schema->load_sims(
      { Album => { name => 'bar1', 'artist.name' => 'foo3' } },
      { object_trace => $trace_file },
    );

    # Verify the trace was written out
    my $trace = LoadFile( $trace_file );
    my $check = hash {
      field objects => array {
        item hash {
          field parent => 0;
          field seen => 1;
          field table => 'Album';
          field spec => hash {
            field name => 'bar1';
            field artist => hash {
              field name => 'foo3';
              end;
            };
            end;
          };
          field made => 2;
          field create_params => hash {
            field name => 'bar1';
            field artist_id => 1;
            end;
          };
          field row => hash {
            field id => 1;
            field name => 'bar1';
            field artist_id => 1;
            end;
          };
          end;
        };
        item hash {
          field parent => 1;
          field via => 'populate_parents/artist';
          field seen => 2;
          field table => 'Artist';
          field spec => hash {
            field name => 'foo3';
            end;
          };
          field made => 1;
          field create_params => hash {
            field name => 'foo3';
            end;
          };
          field row => hash {
            field id => 1;
            field name => 'foo3';
            end;
          };
          end;
        };
        end;
      };
      end;
    };
    is( $trace, $check, 'Toposort trace is as expected' );

    remove_tree( $trace_file );

    return @rv;
  },
  expect => {
    Artist => [
      { id => 1, name => 'foo3' },
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

sims_test "Save object trace with a specified child" => {
  load_sims => sub {
    my ($schema) = @_;

    my $trace_file = '/tmp/trace';

    remove_tree( $trace_file );

    my @rv = $schema->load_sims(
      { Artist => { name => 'foo1', 'albums' => { name => 'bar1' } } },
      { object_trace => $trace_file },
    );

    # Verify the trace was written out
    my $trace = LoadFile( $trace_file );
    my $check = hash {
      field objects => array {
        item hash {
          field parent => 0;
          field seen => 1;
          field table => 'Artist';
          field spec => hash {
            field name => 'foo1';
            field albums => hash {
              field name => 'bar1';
              end;
            };
            end;
          };
          field made => 1;
          field create_params => hash {
            field name => 'foo1';
            end;
          };
          field row => hash {
            field id => 1;
            field name => 'foo1';
            end;
          };
          end;
        };
        item hash {
          field parent => 1;
          field via => 'add_child';
          field seen => 2;
          field table => 'Album';
          field spec => hash {
            field artist_id => 1;
            field name => 'bar1';
            field __META__ => hash {
              field allow_pk_set_value => 1;
              end;
            };
            end;
          };
          field made => 2;
          field create_params => hash {
            field artist_id => 1;
            field name => 'bar1';
            end;
          };
          field row => hash {
            field id => 1;
            field artist_id => 1;
            field name => 'bar1';
            end;
          };
          end;
        };
        end;
      };
      end;
    };
    is( $trace, $check, 'Toposort trace is as expected' );

    remove_tree( $trace_file );

    return @rv;
  },
  expect => {
    Artist => [
      { id => 1, name => 'foo1' },
    ],
  },
  #rv => sub { { Album => shift->{expect}{Album} } },
  addl => {
    created =>  {
      Artist => 1,
      Album => 1,
    },
  },
};

sims_test "Save object trace with children specified by number" => {
  load_sims => sub {
    my ($schema) = @_;

    my $trace_file = '/tmp/trace';

    remove_tree( $trace_file );

    my @rv = $schema->load_sims(
      { Artist => { name => 'foo1', 'albums' => 1 } },
      { object_trace => $trace_file },
    );

    # Verify the trace was written out
    my $trace = LoadFile( $trace_file );
    my $check = hash {
      field objects => array {
        item hash {
          field parent => 0;
          field seen => 1;
          field table => 'Artist';
          field spec => hash {
            field name => 'foo1';
            field albums => 1;
            end;
          };
          field made => 1;
          field create_params => hash {
            field name => 'foo1';
            end;
          };
          field row => hash {
            field id => 1;
            field name => 'foo1';
            end;
          };
          end;
        };
        item hash {
          field parent => 1;
          field via => 'add_child';
          field seen => 2;
          field table => 'Album';
          field spec => hash {
            field artist_id => 1;
            field __META__ => hash {
              field allow_pk_set_value => 1;
              end;
            };
            end;
          };
          field made => 2;
          field create_params => hash {
            field artist_id => 1;
            field name => E;
            end;
          };
          field row => hash {
            field id => 1;
            field artist_id => 1;
            field name => E;
            end;
          };
          end;
        };
        end;
      };
      end;
    };
    is( $trace, $check, 'Toposort trace is as expected' );

    remove_tree( $trace_file );

    return @rv;
  },
  expect => {
    Artist => [
      { id => 1, name => 'foo1' },
    ],
  },
  #rv => sub { { Album => shift->{expect}{Album} } },
  addl => {
    created =>  {
      Artist => 1,
      Album => 1,
    },
  },
};

done_testing;
