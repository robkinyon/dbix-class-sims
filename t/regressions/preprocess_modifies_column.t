# vi:sw=2
use strictures 2;

use Test2::V0 qw( done_testing );

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
          sim => { value => 'abcxyz' },
        },
        derived_name => {
          data_type => 'varchar',
          size => 128,
          is_nullable => 0,
        },
      },
      primary_keys => [ 'id' ],
    },
  ]);
}

use common qw(sims_test);

sims_test "Modify provided value in preprocess" => {
  spec => [
    {
      Artist => [
        { name => 'xyz' },
      ],
    },
    {
      hooks => {
        preprocess => sub {
          my ($name, $source, $item) = @_;
          if ($name eq 'Artist') {
            $item->{name} =~ s/x//;
            $item->{derived_name} //= uc($item->{name});
          }
        },
      },
    },
  ],
  expect => {
    Artist => { id => 1, name => 'yz', derived_name => 'YZ' },
  },
  rv => {
    Artist => { id => 1, name => 'yz', derived_name => 'YZ' },
  },
};

=pod
sims_test "Modify generated value in preprocess" => {
  spec => [
    {
      Artist => 1,
    },
    {
      hooks => {
        preprocess => sub {
          my ($name, $source, $item) = @_;
          if ($name eq 'Artist') {
            $item->{name} =~ s/x//;
            $item->{derived_name} //= uc($item->{name});
          }
        },
      },
    },
  ],
  expect => {
    Artist => { id => 1, name => 'abcyz', derived_name => 'ABCYZ' },
  },
  rv => {
    Artist => { id => 1, name => 'abcyz', derived_name => 'ABCYZ' },
  },
};
=cut

done_testing;
