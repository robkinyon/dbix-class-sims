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
    __PACKAGE__->has_many(
      mansions => 'MyApp::Schema::Result::Mansion' => 'artist_id',
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
    );
    __PACKAGE__->set_primary_key('id');
    __PACKAGE__->belongs_to(
      artist => 'MyApp::Schema::Result::Artist' => 'artist_id',
    );
  }

  {
    package MyApp::Schema::Result::Mansion;
    use base 'DBIx::Class::Core';
    __PACKAGE__->table('mansions');
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
    __PACKAGE__->register_class(Mansion => 'MyApp::Schema::Result::Mansion');
    __PACKAGE__->load_components('Sims');
  }
}

use Test::DBIx::Class qw(:resultsets);

# Create a row with a parent which has a different child specified as well.
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
          {
            name => 'Wonder Years',
            artist => {
              name => 'Superstar',
              mansions => [
                { name => 'My Place' },
              ],
            },
          }
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'Superstar' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'artist_id', 'name' ], Album, [
    [ 1, 1, 'Wonder Years' ],
  ], "Album fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Mansion, [
    [ 1, 'My Place', 1 ],
  ], "Mansion fields are right";

  cmp_deeply( $rv, {
    Album => [ methods(id => 1) ],
  });
}

# Create a row that uses an existing parent which would have had a different
# child specified.
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
          { name => 'Superstar' },
        ],
        Album => [
          {
            name => 'Wonder Years',
            artist => {
              name => 'Superstar',
              mansions => [
                { name => 'My Place' },
              ],
            },
          }
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'Superstar' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'artist_id', 'name' ], Album, [
    [ 1, 1, 'Wonder Years' ],
  ], "Album fields are right";
  is_fields [ 'id', 'name', 'artist_id' ], Mansion, [
  ], "Mansion fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1) ],
    Album  => [ methods(id => 1) ],
  });
}
done_testing;
