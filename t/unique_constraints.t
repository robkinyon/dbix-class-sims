# vi:sw=2
use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::Deep;
use Test::Exception;
use Test::Warn;

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
      first_name => {
        data_type => 'varchar',
        size => 128,
        is_nullable => 0,
        sim => { value => 'Taylor' },
      },
      last_name => {
        data_type => 'varchar',
        size => 128,
        is_nullable => 0,
        sim => { value => 'Swift' },
      },
    );
    __PACKAGE__->set_primary_key('id');
    __PACKAGE__->add_unique_constraint(['first_name', 'last_name']);
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
  note "Load an artist, then try and find that artist with a second load_sims";
  Schema->deploy({ add_drop_table => 1 });

  {
    is Artist->count, 0, "There are no artists loaded at first";
    my $rv;
    lives_ok {
      $rv = Schema->load_sims(
        {
          Artist => [
            { first_name => 'Taylor', last_name => 'Swift' },
          ],
        },
      );
    } "Everything loads ok the first call";

    is_fields [ 'id', 'first_name', 'last_name' ], Artist, [
      [ 1, 'Taylor', 'Swift' ],
    ], "Artist columns are right";
    
    cmp_deeply( $rv, { Artist => [ methods(id => 1) ] } );
  }

  {
    is Artist->count, 1, "There is one artist loaded now";
    my $rv;
    lives_ok {
      $rv = Schema->load_sims(
        {
          Artist => 1,
        },
      );
    } "Everything loads ok the second call";

    is_fields [ 'id', 'first_name', 'last_name' ], Artist, [
      [ 1, 'Taylor', 'Swift' ],
    ], "Artist columns are still right";
    
    cmp_deeply( $rv, { Artist => [ methods(id => 1) ] } );
  }
}

done_testing
