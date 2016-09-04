# vi:sw=2
use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::Deep;
use Test::Exception;
use Test::Trap;
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

my $null_constraint_failure;
if ($DBD::SQLite::VERSION le '1.40') {
  $null_constraint_failure = 'may not be NULL';
}
else {
  $null_constraint_failure = 'NOT NULL constraint failed';
}

subtest "Missing required column" => sub {
  Schema->deploy({ add_drop_table => 1 });

  is Artist->count, 0, "There are no artists loaded at first";
  trap {
    Schema->load_sims(
      {
        Artist => [
          {},
        ],
      },
    );
  };

  is $trap->leaveby, 'die', "load_sims fails";
  is $trap->stdout, '', "No STDOUT";
  like $trap->die, qr/$null_constraint_failure/, "Missing required column";

  is Artist->count, 0, "There are still no artists loaded after load_sims is called with a failure";
};

# If any row fails, the whole things fails.
subtest "Missing required column on some row" => sub {
  Schema->deploy({ add_drop_table => 1 });

  is Artist->count, 0, "There are no artists loaded at first";
  trap {
    Schema->load_sims(
      {
        Artist => [
          { name => 'foo' },
          {},
        ],
      },
    );
  };
  is $trap->leaveby, 'die', "load_sims fails";
  is $trap->stdout, '', "No STDOUT";
  like $trap->die, qr/$null_constraint_failure/, "Missing required column";

  is Artist->count, 0, "There are still no artists loaded after load_sims is called with a failure";

  trap {
    Schema->load_sims(
      {
        Artist => [
          {},
          { name => 'foo' },
        ],
      },
    );
  };
  is $trap->leaveby, 'die', "load_sims fails";
  is $trap->stdout, '', "No STDOUT";
  like $trap->die, qr/$null_constraint_failure/, "Missing required column";

  is Artist->count, 0, "There are still no artists loaded after load_sims is called with a failure";
};

subtest "A single row succeeds" => sub {
  Schema->deploy({ add_drop_table => 1 });

  is Artist->count, 0, "There are no artists loaded at first";
  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
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
  
  cmp_deeply( $rv, { Artist => [ methods(id => 1) ] } );
};

subtest "Load multiple rows" => sub {
  Schema->deploy({ add_drop_table => 1 });

  is Artist->count, 0, "There are no artists loaded at first";
  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
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
  
  cmp_deeply( $rv, { Artist => [ methods(id => 1), methods(id => 2) ] } );
};

# Test passing in a sim type
subtest "Pass in a sim_type" => sub {
  Schema->deploy({ add_drop_table => 1 });

  is Artist->count, 0, "There are no artists loaded at first";
  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => [
          { name => \{ value => 'george' } },
        ],
      },
    );
  } "Everything loads ok";

  my $rs = Artist;
  is Artist->count, 1, "There are now one artist loaded after load_sims is called";
  is_fields [ 'id', 'name', 'hat_color' ], $rs, [
    [ 1, 'george', 'purple' ],
  ], "Artist columns are right";
  
  cmp_deeply( $rv, { Artist => [ methods(id => 1) ] } );
};

Schema->source('Artist')->column_info('name')->{sim}{value} = 'george';

# Verify that passing in a sim spec overrides the existing one.
subtest "Override a sim_type" => sub {
  Schema->deploy({ add_drop_table => 1 });

  is Artist->count, 0, "There are no artists loaded at first";
  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => [
          { name => \{ value => 'bill' } },
        ],
      },
    );
  } "Everything loads ok";

  my $rs = Artist;
  is Artist->count, 1, "There are now one artist loaded after load_sims is called";
  is_fields [ 'id', 'name', 'hat_color' ], $rs, [
    [ 1, 'bill', 'purple' ],
  ], "Artist columns are right";
  
  cmp_deeply( $rv, { Artist => [ methods(id => 1) ] } );
};

# Test the ability to pass in a number instead of a specification for a source
subtest "Set 1 for number of rows" => sub {
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

  my $rs = Artist;
  is $rs->count, 1, "There are now one artist loaded after load_sims is called";
  is_fields [ 'id', 'name', 'hat_color' ], $rs, [
    [ 1, 'george', 'purple' ],
  ], "Artist columns are right";
  
  cmp_deeply( $rv, { Artist => [ methods(id => 1) ] } );
};

subtest "Set 2 for number of rows" => sub {
  Schema->deploy({ add_drop_table => 1 });

  is Artist->count, 0, "There are no artists loaded at first";
  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => 2,
      },
    );
  } "Everything loads ok";

  my $rs = Artist;
  is $rs->count, 2, "There are now two artists loaded after load_sims is called";
  is_fields [ 'id', 'name', 'hat_color' ], $rs, [
    [ 1, 'george', 'purple' ],
    [ 2, 'george', 'purple' ],
  ], "Artist columns are right";
  
  cmp_deeply( $rv, { Artist => [ methods(id => 1), methods(id => 2) ] } );
};

subtest "Provide a hashref for rows" => sub {
  Schema->deploy({ add_drop_table => 1 });

  is Artist->count, 0, "There are no artists loaded at first";
  my $rv;
  lives_ok {
    $rv = Schema->load_sims(
      {
        Artist => {},
      },
    );
  } "Everything loads ok";

  my $rs = Artist;
  is $rs->count, 1, "There are now one artist loaded after load_sims is called";
  is_fields [ 'id', 'name', 'hat_color' ], $rs, [
    [ 1, 'george', 'purple' ],
  ], "Artist columns are right";
  
  cmp_deeply( $rv, { Artist => [ methods(id => 1) ] } );
};

subtest "A scalarref is unknown" => sub {
  Schema->deploy({ add_drop_table => 1 });

  is Artist->count, 0, "There are no artists loaded at first";
  my $rv;
  warning_like {
    $rv = Schema->load_sims(
      {
        Artist => \"",
      },
    );
  } qr/^Skipping Artist - I don't know what to do!/;

  my $rs = Artist;
  is $rs->count, 0, "There are no artists loaded after load_sims is called";
  
  cmp_deeply( $rv, {} );
};

done_testing;
