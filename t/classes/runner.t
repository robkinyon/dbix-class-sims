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
    },
  ]);
}

use common qw(Schema);

use DBIx::Class::Sims::Runner;

my $runner = DBIx::Class::Sims::Runner->new(
  schema => Schema,

  # Other attributes, used only in run() (and its children):
  # parent is only used in fix_columns()
  # toposort => [ 'Artist' ],
  # initial_spec - lists which items are in the original spec
  # spec - requests
  # hooks - hooks
  # constraints - these are requirements on relationships (usually children)
  # allow_pk_set_value => $opts->{allow_pk_set_value} // 0,
  # ignore_unknown_tables => $opts->{ignore_unknown_tables} // 0,
  # allow_relationship_column_names => $opts->{allow_relationship_column_names} // 1,
);

isa_ok($runner, 'DBIx::Class::Sims::Runner', '::Runner builds correctly');
is($runner->schema, Schema, 'The schema() accessor returns correctly');

done_testing;
