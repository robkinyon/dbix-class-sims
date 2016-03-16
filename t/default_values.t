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
      name => {
        data_type => 'varchar',
        size => 128,
        is_nullable => 0,
        default_value => 'George',
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
  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => 1,
      },
    );
  } "Everything loads ok";

  is Artist->count, 1, "There are now one artist loaded after load_sims is called";
  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'George' ],
  ], "Artist columns are right";
  
  cmp_deeply( $rv, { Artist => [ methods(id => 1) ] }, 'Correct rows returned' );
}

done_testing;
