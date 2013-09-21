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
      hat_color => {
        data_type => 'varchar',
        size => 128,
        is_nullable => 1,
        sim => { value => 'purple' },
      },
    );
    __PACKAGE__->set_primary_key('id');
  }

  {
    package MyApp::Schema;
    use base 'DBIx::Class::Schema';
    __PACKAGE__->register_class(Artist => 'MyApp::Schema::Result::Artist');
    __PACKAGE__->load_components('Sims');
  }
}

use Test::DBIx::Class qw(:resultsets);

{
  Schema->deploy({ add_drop_table => 1 });

  is Artist->count, 0, "There are no artists loaded at first";
  throws_ok {
    Schema->load_sims(
      {
        Artist => [
          {},
        ],
      },
    );
  } qr/may not be NULL/, "Missing required column";

  is Artist->count, 0, "There are still no artists loaded after load_sims is called with a failure";
}

# If any row fails, the whole things fails.
{
  Schema->deploy({ add_drop_table => 1 });

  is Artist->count, 0, "There are no artists loaded at first";
  throws_ok {
    Schema->load_sims(
      {
        Artist => [
          { name => 'foo' },
          {},
        ],
      },
    );
  } qr/may not be NULL/, "Missing required column";

  is Artist->count, 0, "There are still no artists loaded after load_sims is called with a failure";

  throws_ok {
    Schema->load_sims(
      {
        Artist => [
          {},
          { name => 'foo' },
        ],
      },
    );
  } qr/may not be NULL/, "Missing required column";

  is Artist->count, 0, "There are still no artists loaded after load_sims is called with a failure";
}

{
  Schema->deploy({ add_drop_table => 1 });

  is Artist->count, 0, "There are no artists loaded at first";
  my $ids;
  lives_ok {
    $ids = Schema->load_sims(
      {
        Artist => [
          { name => 'foo' },
        ],
      },
    );
  } "Everything loads ok";

  my $rs = Artist;
  is Artist->count, 1, "There are now one artist loaded after load_sims is called";
  is_fields [ 'id', 'name', 'hat_color' ], $rs, [
    [ 1, 'foo', 'purple' ],
  ], "Artist columns are right";
  
  cmp_deeply( $ids, { Artist => [ { id => 1 } ] } );
}

{
  Schema->deploy({ add_drop_table => 1 });

  is Artist->count, 0, "There are no artists loaded at first";
  my $ids;
  lives_ok {
    $ids = Schema->load_sims(
      {
        Artist => [
          { name => 'foo' },
          { name => 'bar', hat_color => 'red' },
        ],
      },
    );
  } "Everything loads ok";

  my $rs = Artist;
  is $rs->count, 2, "There are now two artists loaded after load_sims is called";
  is_fields [ 'id', 'name', 'hat_color' ], $rs, [
    [ 1, 'foo', 'purple' ],
    [ 2, 'bar', 'red' ],
  ], "Artist columns are right";
  
  cmp_deeply( $ids, { Artist => [ { id => 1 }, { id => 2 } ] } );
}

# Test the null_chance setting.
Schema->source('Artist')->column_info('name')->{sim}{value} = 'george';
Schema->source('Artist')->column_info('hat_color')->{sim}{null_chance} = 0.3;
my $null_count = 0;
for (1..1000) {
  Schema->deploy({ add_drop_table => 1 });

  Schema->load_sims({ Artist => [ {} ] });

  my ($row) = Artist->all;
  $null_count++ if !defined $row->hat_color;
}
ok( 250 < $null_count && $null_count < 350, "null_chance worked properly ($null_count out of 1000)" );

done_testing;
