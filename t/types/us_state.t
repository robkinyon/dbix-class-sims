# vi:sw=2
use strict;
use warnings FATAL => 'all';

use Test::More;

use lib 't/lib';
use types qw(types_test);

types_test us_state => {
  tests => [
    [ { data_type => 'varchar'}, qr/^\w\w$/, 'AL' ],
    [ { data_type => 'varchar', size => 2 }, qr/^\w\w$/, 'AL' ],
    [ { data_type => 'varchar', size => 10 }, qr/^[\w\s]{1,10}$/, 'Alabama' ],
    [ { data_type => 'varchar', size => 12 }, qr/^[\w\s]{1,12}$/, 'Alabama' ],
  ],
};

done_testing;
