# vi:sw=2
use strictures 2;

use Test::More;
use Test::Deep; # Needed for re() below

use lib 't/lib';

BEGIN {
  use loader qw(build_schema);
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
      might_have => {
        album => { Album => 'artist_id' },
      },
    },
    Album => {
      table => 'albums',
      columns => {
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
      primary_keys => [ 'artist_id' ],
      belongs_to => {
        artist => { Artist => 'artist_id' },
      },
    },
  ]);
}

use common qw(sims_test);

sims_test "parent builds a child, but we're creating a child" => {
  spec => [
    {
      Album => [
        { name => 'bar' },
      ],
    },
    {
      hooks => {
        preprocess => sub {
          my ($name, $source, $item) = @_;
          if ($name eq 'Artist') {
            $item->{album} //= [ {} ];
          }
        },
      },
    },
  ],
  expect => {
    Artist => { id => 1, name => re('.+') },
    Album  => { artist_id => 1, name => 'bar' },
  },
  rv => {
    Album  => { artist_id => 1, name => 'bar' },
  },
};

sims_test "child refers to parent by backref" => {
  spec => [
    {
      Artist => 1,
      Album => { artist_id => \'Artist[0].id' },
    },
  ],
  expect => {
    Artist => { id => 1, name => re('.+') },
    Album  => { artist_id => 1, name => re('.+') },
  },
};

done_testing;
