# vi:sw=2
use strict;
use warnings FATAL => 'all';

use Test::More;

use lib 't/lib';
use types qw(types_test);

types_test ip_address => {
  tests => [
    [ { data_type => 'varchar' }, qr/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/, '0.0.0.0' ],
  ],
  addl_check => sub {
    my ($v) = @_;
    my @parts = split '\.', $v;
    foreach my $part ( @parts ) {
      cmp_ok( $part, '>=', 0 );
      cmp_ok( $part, '<=', 255 );
    }
  },
};

done_testing;
