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
    package MyApp::Schema::Result::Studio;
    use base 'DBIx::Class::Core';
    __PACKAGE__->table('studios');
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
    __PACKAGE__->register_class(Studio => 'MyApp::Schema::Result::Studio');
    __PACKAGE__->load_components('Sims');
  }
}

use Test::DBIx::Class qw(:resultsets);

{
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  throws_ok {
    Schema->load_sims(
      {
        Artist => [
          {},
        ],
        Studio => [
          {},
        ],
      },
    );
  } qr/may not be NULL/, "Missing required column";

  my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
  is $count, 0, "There are no tables loaded after load_sims is called with a failure";
}

{
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  throws_ok {
    Schema->load_sims(
      {
        Artist => [
          { name => 'foo' },
        ],
        Studio => [
          {},
        ],
      },
    );
  } qr/may not be NULL/, "Missing required column";

  my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
  is $count, 0, "There are no tables loaded after load_sims is called with a failure";
}

{
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  throws_ok {
    Schema->load_sims(
      {
        Artist => [
          {},
        ],
        Studio => [
          { name => 'foo' },
        ],
      },
    );
  } qr/may not be NULL/, "Missing required column";

  my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
  is $count, 0, "There are no tables loaded after load_sims is called with a failure";
}

{
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => [
          { name => 'Joe' },
        ],
        Studio => [
          { name => 'foo' },
        ],
      },
    );
  } "Everything loads ok";

  is Artist->count, 1, "There is now one artist loaded after load_sims is called";
  is Studio->count, 1, "There is now one artist loaded after load_sims is called";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'Joe' ],
  ], "Artist id and name is right";
  is_fields [ 'id', 'name' ], Studio, [
    [ 1, 'foo' ],
  ], "Studio id and name is right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1) ],
    Studio => [ methods(id => 1) ],
  });
}

done_testing;
