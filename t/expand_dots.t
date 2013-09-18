use strict;
use warnings FATAL => 'all';

use Test::More;
use Test::Deep;

use_ok 'DBIx::Class::Sims';

my $sub = \&DBIx::Class::Sims::expand_dots;

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
    cmp_deeply( $sub->( $test->{start} ), $test->{expected} );
}

done_testing;
