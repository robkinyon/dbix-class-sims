# This class exists to encapsulate the DBIx::Class::Source object and provide
# Sims-specific functionality to navigate sources and the attributes of
# sources.

package DBIx::Class::Sims::Source;

use 5.010_001;

use strictures 2;

#use Scalar::Util qw( reftype );

sub new {
  my $class = shift;
  my $self = bless {@_}, $class;
  $self->initialize;
  return $self;
}

sub initialize {
  my $self = shift;

  # Do this first so all the other methods work properly.
  $self->{source} = $self->schema->source($self->name);

=pod
  my $is_fk = sub { return exists $_[0]{attrs}{is_foreign_key_constraint} };
  my $cond = sub {
    my $x = $_[0]{cond};
    if (reftype($x) eq 'CODE') {
      $x = $x->({
        foreign_alias => 'foreign',
        self_alias => 'self',
      });
    }
    if (reftype($x) ne 'HASH') {
      die "cond is not a HASH\n" . np($_[0]);
    }
    return $x;
  };
  my $self_fk_cols = sub { map {/^self\.(.*)/; $1} values %{$cond->($_[0])} };

  $self->{in_fk} = {};
  foreach my $rel_name ( $self->relationships ) {
    my $rel_info = $self->relationship_info($rel_name);

    if ($is_fk->($rel_info)) {
      $self->{in_fk}{$_} = 1 for $self_fk_cols->($rel_info);
    }
  }
=cut

  return;
}

sub name   { $_[0]{name}   }
sub runner { $_[0]{runner} }
sub source { $_[0]{source} }

sub schema { $_[0]->runner->schema }

# Delegate the following methods. This will be easier with Moose.
sub relationships { shift->source->relationships(@_) }
sub relationship_info { shift->source->relationship_info(@_) }
sub columns { shift->source->columns(@_) }
sub column_info { shift->source->column_info(@_) }
sub primary_columns { shift->source->primary_columns(@_) }
sub unique_constraint_names { shift->source->unique_constraint_names(@_) }
sub unique_constraint_columns { shift->source->unique_constraint_columns(@_) }

=pod
sub column_in_fk {
  my $self = shift;
  my ($colname) = @_;

  return $self->{in_fk}{$colname};
}
=cut

1;
__END__
