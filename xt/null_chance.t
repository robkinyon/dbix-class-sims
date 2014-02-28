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

Schema->source('Artist')->column_info('name')->{sim}{value} = 'george';

# Test the null_chance setting.
Schema->source('Artist')->column_info('hat_color')->{sim}{null_chance} = 0.3;
my $null_count = 0;
for (1..1000) {
  Schema->deploy({ add_drop_table => 1 });

  Schema->load_sims({ Artist => [ {} ] });

  my ($row) = Artist->all;
  $null_count++ if !defined $row->hat_color;
}
ok( 250 < $null_count && $null_count < 350, "null_chance worked properly ($null_count out of 1000)" );

done_testing;
