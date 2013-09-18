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
  is_fields [ 'id', 'name' ], $rs, [
    [ 1, 'foo' ],
  ], "Artist id and name is right";
  
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
          { name => 'bar' },
        ],
      },
    );
  } "Everything loads ok";

  my $rs = Artist;
  is $rs->count, 2, "There are now two artists loaded after load_sims is called";
  is_fields [ 'id', 'name' ], $rs, [
    [ 1, 'foo' ],
    [ 2, 'bar' ],
  ], "Artist id and name is right";
  
  cmp_deeply( $ids, { Artist => [ { id => 1 }, { id => 2 } ] } );
}


done_testing;
