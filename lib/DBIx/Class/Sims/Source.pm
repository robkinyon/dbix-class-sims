# This class exists to encapsulate the DBIx::Class::Source object and provide
# Sims-specific functionality to navigate sources and the attributes of
# sources.

package DBIx::Class::Sims::Source;

use 5.010_001;

use strictures 2;

use Scalar::Util qw( reftype );

use DBIx::Class::Sims::Relationship;

# Requires the following attributes:
# * name
# * runner
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

  $self->{relationships} = {};
  $self->{in_fk} = {};
  foreach my $rel_name ( $self->source->relationships ) {
    my $r = DBIx::Class::Sims::Relationship->new(
      source => $self,
      name   => $rel_name,
      info   => $self->source->relationship_info($rel_name),
    );
    $self->{relationships}{$rel_name} = $r;

    if ($r->is_fk) {
      $self->{in_fk}{$_} = 1 for $r->self_fk_cols();
    }
  }

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

sub column_in_fk {
  my $self = shift;
  my ($colname) = @_;

  return $self->{in_fk}{$colname};
}

sub my_relationships {
  my $self = shift;
  return $self->{relationships};
}

1;
__END__
