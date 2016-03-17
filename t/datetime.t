# vi:sw=2
use strict;
use warnings FATAL => 'all';

use DateTime;

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
      },
      created_on => {
        data_type => 'timestamp',
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

  my $now = DateTime->now;

  is Artist->count, 0, "There are no artists loaded at first";
  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => [
          { name => 'foo', created_on => $now },
        ],
      },
    );
  } "Everything loads ok";

  my $rs = Artist;
  is Artist->count, 1, "There are now one artist loaded after load_sims is called";

  my $new_now = Schema->storage->datetime_parser->format_datetime($now);
  is_fields [ 'id', 'name', 'created_on' ], $rs, [
    [ 1, 'foo', $new_now ],
  ], "Artist columns are right";

  cmp_deeply( $rv, { Artist => [ methods(id => 1) ] } );
}

{
  Schema->deploy({ add_drop_table => 1 });

  # Try a string instead of a DateTime object.
  my $now = DateTime->now();

  is Artist->count, 0, "There are no artists loaded at first";
  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => [
          { name => 'foo', created_on => "$now" },
        ],
      },
    );
  } "Everything loads ok";

  my $rs = Artist;
  is Artist->count, 1, "There are now one artist loaded after load_sims is called";

  my $new_now = Schema->storage->datetime_parser->format_datetime($now);
  is_fields [ 'id', 'name', 'created_on' ], $rs, [
    [ 1, 'foo', $new_now ],
  ], "Artist columns are right";

  cmp_deeply( $rv, { Artist => [ methods(id => 1) ] } );
}

done_testing;
