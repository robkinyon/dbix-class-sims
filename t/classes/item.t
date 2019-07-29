# vi:sw=2
use strictures 2;

use Test2::V0 qw( done_testing subtest match is );
use Test::Trap; # Needed for trap()

my $item = DBIx::Class::Sims::Item->new(
  runner => undef,
  source => undef,
  spec   => {},
);

package Source {
  sub new { my $c = shift; bless {@_}, $c }
  sub name { shift->{name} }
  sub columns { @{ shift->{columns} } }
  sub relationships { @{ shift->{relationships} } }
}

package Column {
  sub new { my $c = shift; bless {@_}, $c }
  sub name { shift->{name} }
}
sub column { my $n = shift; Column->new(name => $n) }

subtest create_search => sub {
  subtest 'base case' => sub {
    my $source = Source->new(
      name => 'Foo',
      columns => [],
    );
    my ($cond, $extra) = $item->create_search($source, {});
    is( $cond, {}, 'Cond is expected' );
    is( $extra, {}, 'Extra is expected' );
  };

  subtest 'simple case' => sub {
    my $source = Source->new(
      name => 'Foo',
      columns => [ column('a') ],
    );
    my ($cond, $extra) = $item->create_search($source, { a => 1 });
    is( $cond, { a => 1 }, 'Cond is expected' );
    is( $extra, {}, 'Extra is expected' );
  };

  subtest 'column missing' => sub {
    my $source = Source->new(
      name => 'Foo',
      columns => [ column('b') ],
    );
    trap {
      $item->create_search($source, { a => 1 });
    };
    is $trap->leaveby, 'die', 'died as expected';
    is $trap->die . '', match(qr/Foo has no column or relationship 'a'/), 'Error message as expected';
  };

=pod
  subtest 'simple relationship' => sub {
    my $source = Source->new(
      name => 'Foo',
      columns => [ column('a') ],
    );
    my ($cond, $extra) = $item->create_search($source, { a => 1 });
    is( $cond, { a => 1 }, 'Cond is expected' );
    is( $extra, {}, 'Extra is expected' );
  };
=cut
};

done_testing;
