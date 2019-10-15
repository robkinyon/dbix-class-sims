# vi:sw=2
use strict;
use warnings FATAL => 'all';

use Test::More;

use lib 't/lib';
use types qw(types_test);

# The algorithm for email_address creates an unpredictable predictable value.
sub predictable_value {
  my $n = shift;

  my $acct = 'a' x int(($n-5)/2);
  substr($acct, 2, 1) = '+' if length($acct) > 5;

  my $domain = 'a' x int(($n-4)/2);
  substr($domain, 2, 1) = '.' if length($domain) > 5;

  return "${acct}\@${domain}.com";
}

types_test email_address => {
  tests => [
    # Default is 7
    [ { data_type => 'varchar' }, qr/^[\w.+]+@[\w.]+$/, 'a@a.com' ],

    ( map {
      [
        { data_type => 'varchar', size => $_ }, qr/^[\w.+]+@[\w.]+$/,
        predictable_value($_),
      ],
    } 7 .. 100),

    # Anything under 7 characters is too small - "a@b.com" is the smallest legal
    ( map {
      [ { data_type => 'varchar', size => $_ }, qr/^$/ ],
    } 1 .. 6),
  ],
};

done_testing;
