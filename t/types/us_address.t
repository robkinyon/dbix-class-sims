# vi:sw=2
use strict;
use warnings FATAL => 'all';

use Test::More;

use lib 't/lib';
use types qw(types_test);

types_test us_address => {
  tests => [
    [ { data_type => 'varchar' }, qr/^(?:\d{1,5} \w+ [\w.]+)|(?:P\.?O\.? Box \d+)$/, '1 Main Street' ],
  ],
};

done_testing;
