# vi:sw=2
use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::Deep;
use Test::Exception;

BEGIN {
  {
    package MyApp::Schema::Result::House;
    use base 'DBIx::Class::Core';
    __PACKAGE__->table('houses');
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
        sim => {
          func => sub { return 'abcd' },
        },
      },
    );
    __PACKAGE__->set_primary_key('id');
    __PACKAGE__->has_many(
      artists => 'MyApp::Schema::Result::Artist' => 'house_id',
    );
  }

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
        sim => {
          func => sub { return 'abcd' },
        },
      },
      house_id => {
        data_type => 'int',
        is_nullable => 0,
      },
    );
    __PACKAGE__->set_primary_key('id');
    __PACKAGE__->belongs_to(
      house => 'MyApp::Schema::Result::House' => 'house_id',
    );
    __PACKAGE__->has_many(
      albums => 'MyApp::Schema::Result::Album' => 'artist_id',
    );
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
        sim => {
          func => sub { return 'bcde' },
        },
      },
    );
    __PACKAGE__->set_primary_key('id');
    __PACKAGE__->has_many(
      albums => 'MyApp::Schema::Result::Album' => 'studio_id',
    );
  }

  {
    package MyApp::Schema::Result::Album;
    use base 'DBIx::Class::Core';
    __PACKAGE__->table('albums');
    __PACKAGE__->add_columns(
      id => {
        data_type => 'int',
        is_nullable => 0,
        is_auto_increment => 1,
      },
      artist_id => {
        data_type => 'int',
        is_nullable => 0,
      },
      studio_id => {
        data_type => 'int',
        is_nullable => 0,
      },
      name => {
        data_type => 'varchar',
        size => 128,
        is_nullable => 0,
        sim => {
          func => sub { return 'efgh' },
        },
      },
    );
    __PACKAGE__->set_primary_key('id');
    __PACKAGE__->belongs_to(
      artist => 'MyApp::Schema::Result::Artist' => 'artist_id',
    );
    __PACKAGE__->belongs_to(
      studio => 'MyApp::Schema::Result::Studio' => 'studio_id',
    );
    __PACKAGE__->has_many(
      tracks => 'MyApp::Schema::Result::Track' => 'album_id',
    );
  }

  {
    package MyApp::Schema::Result::Track;
    use base 'DBIx::Class::Core';
    __PACKAGE__->table('tracks');
    __PACKAGE__->add_columns(
      track_id => {
        data_type => 'int',
        is_nullable => 0,
        is_auto_increment => 1,
      },
      album_id => {
        data_type => 'int',
        is_nullable => 0,
      },
      name => {
        data_type => 'varchar',
        size => 128,
        is_nullable => 0,
        sim => {
          func => sub { return 'ijkl' },
        },
      },
    );
    __PACKAGE__->set_primary_key('track_id');
    __PACKAGE__->belongs_to(
      album => 'MyApp::Schema::Result::Album' => 'album_id',
    );
  }

  {
    package MyApp::Schema;
    use base 'DBIx::Class::Schema';
    __PACKAGE__->register_class(House => 'MyApp::Schema::Result::House');
    __PACKAGE__->register_class(Artist => 'MyApp::Schema::Result::Artist');
    __PACKAGE__->register_class(Studio => 'MyApp::Schema::Result::Studio');
    __PACKAGE__->register_class(Album => 'MyApp::Schema::Result::Album');
    __PACKAGE__->register_class(Track => 'MyApp::Schema::Result::Track');
    __PACKAGE__->load_components('Sims');
  }
}

use Test::DBIx::Class qw(:resultsets);

subtest "Autogenerate ancestors (2 lineages)" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Track => [
          {},
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], House, [
    [ 1, 'abcd' ],
  ], "House fields are right";
  is_fields [ 'id', 'name', 'house_id' ], Artist, [
    [ 1, 'abcd', 1 ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name' ], Studio, [
    [ 1, 'bcde' ],
  ], "Studio fields are right";
  is_fields [ 'id', 'name', 'artist_id', 'studio_id' ], Album, [
    [ 1, 'efgh', 1, 1 ],
  ], "Album fields are right";
  is_fields [ 'track_id', 'name', 'album_id' ], Track, [
    [ 1, 'ijkl', 1 ],
  ], "Track fields are right";

  cmp_deeply( $rv, {
    Track => [ methods(track_id => 1) ],
  });
};

subtest "Autogenerate 3 parent-layers deep" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Track => [
          { 'album.artist.house.name' => 'Mansion' },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], House, [
    [ 1, 'Mansion' ],
  ], "House fields are right";
  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'abcd' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name' ], Studio, [
    [ 1, 'bcde' ],
  ], "Studio fields are right";
  is_fields [ 'id', 'name', 'artist_id', 'studio_id' ], Album, [
    [ 1, 'efgh', 1, 1 ],
  ], "Album fields are right";
  is_fields [ 'track_id', 'name', 'album_id' ], Track, [
    [ 1, 'ijkl', 1 ],
  ], "Track fields are right";

  cmp_deeply( $rv, {
    Track => [ methods(track_id => 1) ],
  });
};

subtest "Consume a specified 3 parent-layers deep" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  lives_ok {
    Schema->load_sims({
      House => [
        { id => 1, name => 'Mansion2' },
        { id => 3, name => 'Mansion' },
      ],
    });
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Track => [
          { 'album.artist.house.name' => 'Mansion' },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], House, [
    [ 1, 'Mansion2' ],
    [ 3, 'Mansion' ],
  ], "House fields are right";
  is_fields [ 'id', 'name', 'house_id' ], Artist, [
    [ 1, 'abcd', 3 ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name' ], Studio, [
    [ 1, 'bcde' ],
  ], "Studio fields are right";
  is_fields [ 'id', 'name', 'artist_id', 'studio_id' ], Album, [
    [ 1, 'efgh', 1, 1 ],
  ], "Album fields are right";
  is_fields [ 'track_id', 'name', 'album_id' ], Track, [
    [ 1, 'ijkl', 1 ],
  ], "Track fields are right";

  cmp_deeply( $rv, {
    Track => [ methods(track_id => 1) ],
  });
};

subtest "Autogenerate 2 parent-layers deep" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Track => [
          { 'album.artist.name' => 'John' },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'John' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name' ], Studio, [
    [ 1, 'bcde' ],
  ], "Studio fields are right";
  is_fields [ 'id', 'name', 'artist_id', 'studio_id' ], Album, [
    [ 1, 'efgh', 1, 1 ],
  ], "Album fields are right";
  is_fields [ 'track_id', 'name', 'album_id' ], Track, [
    [ 1, 'ijkl', 1 ],
  ], "Track fields are right";

  cmp_deeply( $rv, {
    Track => [ methods(track_id => 1) ],
  });
};

subtest "Create a parent with a child and other parent autogenerate" => sub {
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
          {
            albums => [ {} ],
          },
        ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'abcd' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name' ], Studio, [
    [ 1, 'bcde' ],
  ], "Studio fields are right";
  is_fields [ 'id', 'name', 'artist_id', 'studio_id' ], Album, [
    [ 1, 'efgh', 1, 1 ],
  ], "Album fields are right";
  is_fields [ 'track_id', 'name', 'album_id' ], Track, [
  ], "Track fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1) ],
  });
};

subtest "Create 2 parents, each specifying same child, only 1 child" => sub {
  Schema->deploy({ add_drop_table => 1 });

  {
    my $count = grep { $_ != 0 } map { ResultSet($_)->count } Schema->sources;
    is $count, 0, "There are no tables loaded at first";
  }

  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => [ { albums => [ { name => 'child1' } ] } ],
        Studio => [ { albums => [ { name => 'child1' } ] } ],
      },
    );
  } "load_sims runs to completion";

  is_fields [ 'id', 'name' ], Artist, [
    [ 1, 'abcd' ],
  ], "Artist fields are right";
  is_fields [ 'id', 'name' ], Studio, [
    [ 1, 'bcde' ],
  ], "Studio fields are right";
  is_fields [ 'id', 'name', 'artist_id', 'studio_id' ], Album, [
    [ 1, 'child1', 1, 1 ],
  ], "Album fields are right";
  is_fields [ 'track_id', 'name', 'album_id' ], Track, [
  ], "Track fields are right";

  cmp_deeply( $rv, {
    Artist => [ methods(id => 1) ],
    Studio => [ methods(id => 1) ],
  });
};

done_testing;
