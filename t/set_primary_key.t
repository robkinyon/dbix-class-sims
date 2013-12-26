# vi:sw=2
use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::Deep;
use Test::Exception;
use Test::Warn;

BEGIN {
  {
    package MyApp::Schema::Result::Country;
    use base 'DBIx::Class::Core';
    __PACKAGE__->table('countries');
    __PACKAGE__->add_columns(
      code => {
        data_type   => 'char',
        size        => 2,
        is_nullable => 0,
        sim => { value => 'US' },
      },
    );
    __PACKAGE__->set_primary_key('code');
  }

  {
    package MyApp::Schema;
    use base 'DBIx::Class::Schema';
    __PACKAGE__->register_class(Country => 'MyApp::Schema::Result::Country');
    __PACKAGE__->load_components('Sims');
  }
}

use Test::DBIx::Class qw(:resultsets);

{
  Schema->deploy({ add_drop_table => 1 });

  is Country->count, 0, "There are no countries loaded at first";
  lives_ok {
    Schema->load_sims(
      {
        Country => [
          {},
        ],
      },
    );
  } "Everything loads ok";

  is Country->count, 1, "Country was added";
  is Country->first->code, 'US', 'Country code is US';
}

{
  Schema->deploy({ add_drop_table => 1 });

  is Country->count, 0, "There are no countries loaded at first";
  lives_ok {
    Schema->load_sims(
      {
        Country => [
          { code => 'UK' },
        ],
      },
    );
  } "Everything loads ok";

  is Country->count, 1, "Country was added";
  is Country->first->code, 'UK', 'Country code is UK';
}

done_testing;
