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

subtest 'parent' => sub {
  my $artist = DBIx::Class::Sims::Source->new(
    name   => 'Artist',
    runner => $runner,
  );

  isa_ok($artist, 'DBIx::Class::Sims::Source', '::Source(Artist) builds correctly');
  is($artist->runner, $runner, 'The runner() accessor returns correctly');

  ok(!$artist->column_in_fk('id'), 'artist.id is NOT in a FK');
  ok(!$artist->column_in_fk('name'), 'artist.name is NOT in a FK');

  my @rels = map { $_->name } $artist->relationships;
  cmp_bag(\@rels, ['albums'], "One relationships overall");

  my @parent_rels = map { $_->name } $artist->parent_relationships;
  cmp_bag(\@parent_rels, [], "No parent relationships");

  my @child_rels = map { $_->name } $artist->child_relationships;
  cmp_bag(\@child_rels, ['albums'], "One child relationships");
};

subtest 'child' => sub {
  my $album = DBIx::Class::Sims::Source->new(
    name   => 'Album',
    runner => $runner,
  );
  isa_ok($album, 'DBIx::Class::Sims::Source', '::Source(Album) builds correctly');
  is($album->runner, $runner, 'The runner() accessor returns correctly');
  ok(!$album->column_in_fk('id'), 'album.id is NOT in a FK');
  ok(!$album->column_in_fk('name'), 'album.name is NOT in a FK');
  ok($album->column_in_fk('artist_id'), 'album.artist_id IS in a FK');

  my @rels = map { $_->name } $album->relationships;
  cmp_bag(\@rels, ['artist'], "One relationships overall");

  my @parent_rels = map { $_->name } $album->parent_relationships;
  cmp_bag(\@parent_rels, ['artist'], "One parent relationships");

  my @child_rels = map { $_->name } $album->child_relationships;
  cmp_bag(\@child_rels, [], "No child relationships");
};

done_testing;
