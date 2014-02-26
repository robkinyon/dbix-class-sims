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
      },
      email => {
        data_type => 'varchar',
        size => 128,
        sim => { type => 'email_address' },
      },
    );
    __PACKAGE__->set_primary_key('id');
  }

  {
    package MyApp::Schema;
    use base 'DBIx::Class::Schema';
    __PACKAGE__->register_class(Artist => 'MyApp::Schema::Result::Artist');
  }
}

use Test::DBIx::Class qw(:resultsets);
use DBIx::Class::Sims;

my $email;
my $seed;
{
  Schema->deploy({ add_drop_table => 1 });

  my ($rv, $addl);
  lives_ok {
    ($rv, $addl) = DBIx::Class::Sims->load_sims(Schema,
      {
        Artist => [
          { name => 'Joe' },
        ],
      },
    );
  } "Everything loads ok";
  $seed = $addl->{seed};

  is Artist->count, 1, "There is now one artist loaded after load_sims is called";

  $email = (Artist->all)[0]->email;
  is_fields [ 'id', 'name', 'email' ], Artist, [
    [ 1, 'Joe', $email ],
  ], "Artist columns are correct";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1, name => 'Joe', email => $email) ],
  });
}

{
  Schema->deploy({ add_drop_table => 1 });

  my $rv;
  lives_ok {
    $rv = DBIx::Class::Sims->load_sims(Schema,
      {
        Artist => [
          { name => 'Joe' },
        ],
      },
      {
        seed => $seed,
      },
    );
  } "Everything loads ok";

  is Artist->count, 1, "There is now one artist loaded after load_sims is called";

  is_fields [ 'id', 'name', 'email' ], Artist, [
    [ 1, 'Joe', $email ],
  ], "Artist columns are correct";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1, name => 'Joe', email => $email) ],
  });
}

done_testing;
