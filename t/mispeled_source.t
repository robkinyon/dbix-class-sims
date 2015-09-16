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

use Test::DBIx::Class -connect_opts => {
  on_connect_do => 'PRAGMA foreign_keys = ON'
}, qw(:resultsets);

{
  Schema->deploy({ add_drop_table => 1 });

  is Artist->count, 0, "There are no artists loaded at first";
  throws_ok {
    Schema->load_sims(
      {
        Artiste => [
          {},
        ],
      },
    );
  } qr/Not every specification was used/, "Missing required column";

  is Artist->count, 0, "There are still no artists loaded after load_sims is called with a failure";
}

done_testing;
