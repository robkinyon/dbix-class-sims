# vi:sw=2
use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::Deep;
use Test::Exception;

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
}

use Test::DBIx::Class qw(:resultsets);

# Fail to create
{
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  throws_ok {
    Schema->load_sims(
      {
        Album => [
          {},
        ],
      },
    );
  } qr/artists\.name/i, "load_sims dies with a failure";

  my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
  is $count, 0, "There are no tables loaded after load_sims is called with a failure";
}

# Connect by id
{
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
  };

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
}

# Connect by name
{
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
}

# Auto-generate a parent with a name
{
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
}

# Connect to a random parent
{
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
}

# Pick a random one of multiple choices.
{
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
}

# Multiple rows connect to the same random parent
{
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
}

# Generate a child
{
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
}

# Specify that the names should be auto-generated if necessary.
Schema->source('Artist')->column_info('name')->{sim} = {
  func => sub { return 'abcd' },
};
Schema->source('Album')->column_info('name')->{sim} = {
  func => sub { return 'efgh' },
};

# Auto-generate the parent as necessary
{
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
}

# Auto-generate a child
{
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
        Artist => { albums => 1 },
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
}

# Auto-generate a child each for two artists
{
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
        Artist => { albums => 1 },
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
}

# Specify the ID of the artist
{
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
        Artist => { albums => 1 },
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
}

# Auto-generate a parent with a name
{
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
}

# Specify the name of the child
{
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
        Artist => { albums => 1 },
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
}

# Specify multiple children (more than the minimum)
{
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
        Artist => { albums => 1 },
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
}

# Specify multiple albums with multiple children (more than the minimum)
{
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
}

# Auto-generate multiple children
{
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
        Artist => { albums => 2 },
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
}

done_testing;
