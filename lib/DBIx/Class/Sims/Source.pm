# This class exists to encapsulate the DBIx::Class::Source object and provide
# Sims-specific functionality to navigate sources and the attributes of
# sources.

package DBIx::Class::Sims::Source;

use 5.010_001;

use strictures 2;

use DDP;

use DBIx::Class::Sims::Column;
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
  $self->{source} = $self->runner->schema->source($self->name);

  $self->{columns} = {};
  foreach my $col_name ( $self->source->columns ) {
    my $c = DBIx::Class::Sims::Column->new(
      source => $self,
      name   => $col_name,
      info   => $self->source->column_info($col_name),
    );
    $self->{columns}{$col_name} = $c;
  }

  foreach my $col ( $self->source->primary_columns ) {
    $self->{columns}{$col}->in_pk;
  }

  $self->{uniques} = {};
  foreach my $uk ( $self->source->unique_constraint_names ) {
    $self->{uniques}{$uk} = [];
    foreach my $col ( $self->source->unique_constraint_columns($uk) ) {
      push @{$self->{uniques}{$uk}}, $self->{columns}{$col};
      $self->{columns}{$col}->in_uk($uk);
    }
  }

  $self->{relationships} = {};
  my $constraints = delete($self->{constraints}) // {};
  foreach my $rel_name ( $self->source->relationships ) {
    my $r = DBIx::Class::Sims::Relationship->new(
      source => $self,
      name   => $rel_name,
      info   => $self->source->relationship_info($rel_name),
      constraints => $constraints->{$rel_name},
    );
    $self->{relationships}{$rel_name} = $r;

    if ($r->is_fk) {
      $self->{columns}{$_}->in_fk($r) for $r->self_fk_cols;
    }
  }

  return;
}

sub name   { $_[0]{name}   }
sub runner { $_[0]{runner} }
sub source { $_[0]{source} }

sub columns {
  my $self = shift;
  return values %{$self->{columns}};
}
sub column {
  my $self = shift;
  return unless exists $self->{columns}{$_[0]};
  return $self->{columns}{$_[0]};
}

sub columns_not_in_parent_relationships {
  my $self = shift;

  my %c = map { $_->name => $_ } $self->columns;
  foreach my $r ( $self->parent_relationships ) {
    delete $c{$r->self_fk_col};
  }

  return values %c;
}

sub relationships {
  my $self = shift;
  return values %{$self->{relationships}};
}
sub relationship {
  my $self = shift;
  return unless exists $self->{relationships}{$_[0]};
  return $self->{relationships}{$_[0]};
}

sub uniques {
  my $self = shift;
  return values %{$self->{uniques}};
}

sub parent_relationships {
  my $self = shift;

  return grep { $_->is_fk } $self->relationships;
}

sub child_relationships {
  my $self = shift;

  return grep { !$_->is_fk } $self->relationships;
}

sub resultset {
  my $self = shift;
  return $self->runner->schema->resultset($self->name);
}

sub unique_columns {
  my $self = shift;
  return map {
    [ $self->source->unique_constraint_columns($_) ]
  } $self->source->unique_constraint_names();
}

################################################################################
# There are no tests for the methods below here to the end of the file.

# This is used to determine if additional constraints need to be added when
# looking for a parent row that already exists. The use of this method needs to
# be upgraded to optionally throw an error if the parent found would not meet
# the other requirements on the parent.
sub unique_constraints_containing {
  my $self = shift;
  my ($column) = @_;

  # Only return true if the unique constraint is solely built from the column.
  # When we handle multi-column relationships, then we will need to handle the
  # situation where the relationship's columns are the UK.
  #
  # The situation where the UK has multiple columns, one of which is the the FK,
  # is potentially undecideable.
  return grep {
    my $col_def = $_;
    ! grep { $column ne $_ } @$col_def
  } $self->unique_columns;
}

sub find_inverse_relationships {
  my $self = shift;
  my ($fksource, $fkcol) = @_;

  my @inverses;
  foreach my $r ( $fksource->relationships ) {

    # Skip relationships that aren't back towards the table we're coming from.
    # TODO: ::Relationship should connect to both ::Source's (source / target)
    next unless $r->short_fk_source eq $self->name;

    # Assumption: We don't need to verify the $fkcol because there shouldn't be
    # multiple relationships on different columns between the same tables. This
    # is likely to be violated, but only by badly-designed schemas.

    push @inverses, {
      rel => $r->name,
      col => $r->foreign_fk_col,
    };
  }

  return @inverses;
}

1;
__END__
