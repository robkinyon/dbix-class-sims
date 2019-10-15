# vi:sw=2
use strict;
use warnings FATAL => 'all';

use Test::More;

use lib 't/lib';
use types qw(types_test);

types_test us_ssntin => {
  tests => [
    [ { data_type => 'varchar' }, qr/^(?:\d{3}-\d{2}-\d{4})|(?:\d{2}-\d{7})$/, '000-00-0000' ],
  ],
};

done_testing;
