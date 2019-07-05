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

use common qw( Schema );

my $runner = DBIx::Class::Sims::Runner->new(
  # Other attributes aren't needed for these tests
  schema => Schema,
);

my $artist = DBIx::Class::Sims::Source->new(
  name   => 'Artist',
  runner => $runner,
);

isa_ok($artist, 'DBIx::Class::Sims::Source', '::Source(Artist) builds correctly');
is($artist->schema, Schema, 'The schema() accessor returns correctly');

ok(!$artist->column_in_fk('id'), 'artist.id is not in a FK');
ok(!$artist->column_in_fk('name'), 'artist.name is not in a FK');

my $album = DBIx::Class::Sims::Source->new(
  name   => 'Album',
  runner => $runner,
);
isa_ok($album, 'DBIx::Class::Sims::Source', '::Source(Album) builds correctly');
is($album->schema, Schema, 'The schema() accessor returns correctly');
ok(!$album->column_in_fk('id'), 'album.id is not in a FK');
ok(!$album->column_in_fk('name'), 'album.name is not in a FK');
ok($album->column_in_fk('artist_id'), 'album.artist_id IS in a FK');

done_testing;
