# vi:sw=2
package # Hide from PAUSE
  t::common;

use strict;
use warnings FATAL => 'all';

use base 'Exporter';
our @EXPORT_OK = qw(
  sims_test
);

use Test::More;
use Test::Deep;
use Test::Exception;
use Test::Trap;

use Test::DBIx::Class qw(:resultsets);

sub sims_test ($$) {
  my ($name, $opts) = @_;

  subtest $name => sub {
    Schema->deploy({ add_drop_table => 1 }) if $opts->{deploy} // 1;

    foreach my $name (Schema->sources) {
      my $c = ResultSet($name)->count;
      my $l = $opts->{loaded}{$name} // 0;
      cmp_ok $c, '==', $l, "$name has $l rows loaded at first";
    }

    my ($rv, $addl);
    if ($opts->{dies}) {
      dies_ok {
        ($rv, $addl) = Schema->load_sims($opts->{spec} // {})
      } "load_sims does NOT run to completion";
    }
    else {
      if ($opts->{load_sims}) {
        lives_ok {
          ($rv, $addl) = $opts->{load_sims}->(Schema)
        } "load_sims runs to completion";
      }
      else {
        lives_ok {
          ($rv, $addl) = Schema->load_sims($opts->{spec} // {})
        } "load_sims runs to completion";
      }

      while (my ($name, $expect) = each %{$opts->{expect}}) {
        cmp_deeply(
          [ ResultSet($name)->all ],
          [ map { methods(%$_) } @$expect ],
          "Rows in database for $name are expected",
        );
      }

      my $expected_rv = {};
      while (my ($n,$e) = each %{$opts->{rv} // $opts->{expect}}) {
        $expected_rv->{$n} = [ map { methods(%$_) } @$e ];
      }
      cmp_deeply($rv, $expected_rv, "Return value is as expected");

      if ($opts->{addl}) {
        # Don't force me to set these things, unless I want to.
        $opts->{addl}{duplicates} //= {};
        $opts->{addl}{seed} //= re(qr/^[\d.]+$/);
        cmp_deeply($addl, $opts->{addl}, "Additional value is as expected");
      }
    }
  };
}

1;
