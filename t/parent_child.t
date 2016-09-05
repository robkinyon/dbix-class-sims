# vi:sw=2
use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::Deep;
use Test::Exception;
use Test::Trap;

BEGIN {
  {
    package MyApp::Schema::Result::Artist;
    use base 'DBIx::Class::Core';
    __PACKAGE__->table('artists');
    __PACKAGE__->add_columns(
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
    );
    __PACKAGE__->set_primary_key('id');
    __PACKAGE__->has_many(
      albums => 'MyApp::Schema::Result::Album' => 'artist_id',
    );
  }

  {
    package MyApp::Schema::Result::Album;
    use base 'DBIx::Class::Core';
    __PACKAGE__->table('albums');
    __PACKAGE__->add_columns(
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
      other_name => {
        data_type => 'varchar',
        size => 128,
        is_nullable => 1,
      },
    );
    __PACKAGE__->set_primary_key('id');
    __PACKAGE__->belongs_to(
      artist => 'MyApp::Schema::Result::Artist' => 'artist_id',
    );
  }

  {
    package MyApp::Schema;
    use base 'DBIx::Class::Schema';
    __PACKAGE__->register_class(Artist => 'MyApp::Schema::Result::Artist');
    __PACKAGE__->register_class(Album => 'MyApp::Schema::Result::Album');
    __PACKAGE__->load_components('Sims');
  }
};

use Test::DBIx::Class qw(:resultsets);

subtest "Cannot create child when parent fails" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  trap {
    Schema->load_sims(
      {
        Album => [
          {},
        ],
      },
    );
  };
  is $trap->leaveby, 'die', "load_sims fails";
  is $trap->stdout, '', "No STDOUT";
  like $trap->die,  qr/artists\.name/i, "load_sims dies with a failure";

  my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
  is $count, 0, "There are no tables loaded after load_sims is called with a failure";
};;

subtest "Connect parent/child by id" => sub {
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
          { name => 'foo' },
        ],
        Album => [
          { name => 'bar', 'artist_id' => 1 },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'foo' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'bar', 1 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1) ],
    Album => [ methods(id => 1) ],
  });
};;

subtest "Connect parent/child by lookup" => sub {
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
          { name => 'foo1' },
          { name => 'foo2' },
          { name => 'foo3' },
          { name => 'foo4' },
        ],
        Album => [
          { name => 'bar1', 'artist.name' => 'foo3' },
          { name => 'bar2', 'artist.name' => 'foo1' },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'foo1' ],
    [ 2, 'foo2' ],
    [ 3, 'foo3' ],
    [ 4, 'foo4' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'bar1', 3 ],
    [ 2, 'bar2', 1 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1), methods(id => 2), methods(id => 3), methods(id => 4) ],
    Album => [ methods(id => 1), methods(id => 2) ],
  });
};

subtest "Connect parent/child by object in relationship" => sub {
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
          { name => 'foo1' },
          { name => 'foo2' },
          { name => 'foo3' },
          { name => 'foo4' },
        ],
      }
    );

    $rv = Schema->load_sims(
      {
        Album => [
          { name => 'bar1', artist => $rv->{Artist}[2] },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'foo1' ],
    [ 2, 'foo2' ],
    [ 3, 'foo3' ],
    [ 4, 'foo4' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'bar1', 3 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Album => [ methods(id => 1) ],
  });
};

subtest "Autogenerate a parent with a name" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my ($rv, $addl);
  lives_ok {
    ($rv, $addl) = Schema->load_sims(
      {
        Album => [
          { name => 'bar1', 'artist.name' => 'foo3' },
          { name => 'bar2', 'artist.name' => 'foo1' },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'foo3' ],
    [ 2, 'foo1' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'bar1', 1 ],
    [ 2, 'bar2', 2 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Album => [ methods(id => 1), methods(id => 2) ],
  });

  cmp_deeply( $addl->{created}, {
    Album => 2,
    Artist => 2,
  });
};

subtest "Connect to a random parent" => sub {
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
          { name => 'foo' },
        ],
        Album => [
          { name => 'bar' },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'foo' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'bar', 1 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1) ],
    Album => [ methods(id => 1) ],
  });
};

subtest "Pick a random parent out of multiple choices" => sub {
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
          { name => 'foo' },
          { name => 'foo2' },
        ],
        Album => [
          { name => 'bar' },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'foo' ],
    [ 2, 'foo2' ],
  ], "Artist fields are right";

  # This should work, but doesn't. Opened RT#87799 against Test::DBIx::Class.
  #use Test::Deep;
  #is_fields [ 'id', 'name', 'artist_id' ], Album, [
  #  [ 1, 'bar', re('1|2') ],
  #], "Album fields are right";

  my ($row) = Album->all;
  is($row->id, 1, "Album id is right");
  is($row->name, 'bar', "Album name is right");
  like($row->artist_id, qr/^[12]$/, "Album artist_id is in the right range");

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1), methods(id => 2) ],
    Album => [ methods(id => 1) ],
  });
};

subtest "Multiple rows connect to the same available parent" => sub {
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
          { name => 'foo' },
        ],
        Album => [
          { name => 'bar' },
          { name => 'baz' },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'foo' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'bar', 1 ],
    [ 2, 'baz', 1 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1) ],
    Album => [ methods(id => 1), methods(id => 2) ],
  });
};

subtest "Auto-generate a child with a value" => sub {
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
            'albums' => [
              { name => 'bar' },
            ],
          },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'foo' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'bar', 1 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1) ],
  });
};

# Specify that the names should be auto-generated if necessary.
DBIx::Class::Sims->add_sim( Schema, 'Artist', 'name', {
  func => sub { return 'abcd' },
});
DBIx::Class::Sims->add_sim( Schema, 'Album', 'name', {
  func => sub { return 'efgh' },
});

subtest "Auto-generate a parent as necessary" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Album => [
          {},
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'abcd' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'efgh', 1 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Album => [ methods(id => 1) ],
  });
};

subtest "Force the creation of a parent" => sub {
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
          { name => 'foo' },
          { name => 'foo2' },
        ],
        Album => [
          { name => 'bar', artist => { __META__ => { create => 1 } } },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'foo' ],
    [ 2, 'foo2' ],
    [ 3, 'abcd' ],
  ], "Artist fields are right";

  # This should work, but doesn't. Opened RT#87799 against Test::DBIx::Class.
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'bar', 3 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1), methods(id => 2) ],
    Album => [ methods(id => 1) ],
  });
};

subtest "Use a constraint to force a child row" => sub {
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
          Artist => { albums => 1 },
        },
      }
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'abcd' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'efgh', 1 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1) ],
  });
};

subtest "Use a constraint to force a child row (multiple parents)" => sub {
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
          {}, {},
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
    [ 2, 'abcd' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Album, [
    [ 1, 'efgh', 1 ],
    [ 2, 'efgh', 2 ],
  ], "Album fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1), methods(id => 2) ],
  });
};

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
