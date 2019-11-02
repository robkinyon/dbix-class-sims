# vi:sw=2
use strictures 2;

use Test2::V0 qw(
  done_testing
);

use lib 't/lib';

use File::Path qw( remove_tree );
use YAML::Any qw( LoadFile );

BEGIN {
  use loader qw(build_schema);
  build_schema([
    Artist => {
      table => 'artists',
      columns => {
        name => {
          data_type => 'varchar',
          size => 128,
          is_nullable => 0,
        },
      },
      primary_keys => [ 'name' ],
      has_many => {
        albums => { Album => 'artist_name' },
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
        artist_name => {
          data_type => 'varchar',
          size => 128,
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
        artist => { Artist => 'artist_name' },
      },
    },
  ]);
}

use common qw(sims_test Schema);

{
  local Schema->source('Album')->column_info('artist_name')->{sim}{value} = 'foo';
  sims_test "Connect parent/child by sim" => {
    spec => {
      Artist => [
        { name => 'notfoo' },
        { name => 'foo' },
        { name => 'otherfoo' },
      ],
      Album => { name => 'bar' },
    },
    expect => {
      Artist => [
        { name => 'notfoo' },
        { name => 'foo' },
        { name => 'otherfoo' },
      ],
      Album  => [
        { id => 1, name => 'bar', artist_name => 'foo' },
      ],
    },
  };
}

done_testing;
