use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::Deep;

use_ok 'DBIx::Class::Sims';

my $sub = \&DBIx::Class::Sims::massage_input;

BEGIN {
  {
    package MyApp::Schema;
    use base 'DBIx::Class::Schema';
    __PACKAGE__->load_components('Sims');
  }
}

use Test::DBIx::Class qw(:resultsets);

my @tests = (
  {
    start => {},
    expected => {},
  },
  {
    start => { abcd => [] },
    expected => { abcd => [] }
  },
  {
    start => { abcd => [ { a => 'b' } ] },
    expected => { abcd => [ { a => 'b' } ] },
  },
  {
    start => { abcd => [ { 'a.b' => 'c' } ] },
    expected => { abcd => [ { a => { 'b' => 'c' } } ] },
  },
  {
    start => { abcd => [ { 'a.b.c' => 'd' } ] },
    expected => { abcd => [ { a => { 'b' => { 'c' => 'd' } } } ] },
  },
);

foreach my $test ( @tests ) {
  cmp_deeply( $sub->( Schema, $test->{start} ), $test->{expected} );
}

done_testing;
