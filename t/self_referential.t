# vi:sw=2
use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::Deep;
use Test::Exception;
use Test::Warn;

BEGIN {
  {
    package MyApp::Schema::Result::Company;
    use base 'DBIx::Class::Core';
    __PACKAGE__->table('companies');
    __PACKAGE__->add_columns(
      id => {
        data_type => 'int',
        is_nullable => 0,
        is_auto_increment => 1,
        extra       => { unsigned => 1 },
      },
      parent_id => {
        data_type   => 'int',
        is_nullable => 1,
        is_numeric  => 1,
        extra       => { unsigned => 1 },
      },
    );
    __PACKAGE__->set_primary_key('id');
    __PACKAGE__->belongs_to( 'parent' => 'MyApp::Schema::Result::Company' => { "foreign.id" => "self.parent_id" } );
    __PACKAGE__->has_many( 'children' => 'MyApp::Schema::Result::Company' => { "foreign.parent_id" => "self.id" } );
    #__PACKAGE__->has_many( 'parents' => 'MyApp::Schema::Result::Company' => { "foreign.id" => "self.parent_id" }, { cascade_delete => 0, cascade_copy => 0 } );
  }

  {
    package MyApp::Schema;
    use base 'DBIx::Class::Schema';
    __PACKAGE__->register_class(Company => 'MyApp::Schema::Result::Company');
    __PACKAGE__->load_components('Sims');
  }
}

use Test::DBIx::Class qw(:resultsets);

{
  Schema->deploy({ add_drop_table => 1 });

  is Company->count, 0, "There are no companies loaded at first";
  throws_ok {
    Schema->load_sims(
      {
        Company => [
          {},
        ],
      },
    );
  } qr/expected directed acyclic graph/, "Throws the right exception";

  is Company->count, 0, "No company was added";
}

{
  Schema->deploy({ add_drop_table => 1 });

  is Company->count, 0, "There are no companies loaded at first";
  lives_ok {
    Schema->load_sims(
      {
        Company => [
          {},
        ],
      }, {
        toposort => {
          skip => {
            Company => [ 'parent' ],
          },
        },
      },
    );
  } "Everything loads ok";

  is Company->count, 1, "One company was added";
}

{
  Schema->deploy({ add_drop_table => 1 });

  is Company->count, 0, "There are no companies loaded at first";
  lives_ok {
    Schema->load_sims(
      {
        Company => [
          { parent => {} },
        ],
      }, {
        toposort => {
          skip => {
            Company => [ 'parent' ],
          },
        },
      },
    );
  } "Everything loads ok";

  is Company->count, 2, "Two companies were added";
}

{
  Schema->deploy({ add_drop_table => 1 });

  is Company->count, 0, "There are no companies loaded at first";
  lives_ok {
    Schema->load_sims(
      {
        Company => [
          { children => [ {}, {} ] },
        ],
      }, {
        toposort => {
          skip => {
            Company => [ 'parent' ],
          },
        },
      },
    );
  } "Everything loads ok";

  is Company->count, 3, "Three companies were added";
}

done_testing;
