# This class exists to encapsulate the DBIx::Class::Source object and provide
# Sims-specific functionality to navigate sources and the attributes of
# sources.

package DBIx::Class::Sims::Source;

use 5.010_001;

use strictures 2;

#use DBIx::Class::Sims::Util ();

sub new {
  my $class = shift;
  my $self = bless {@_}, $class;
  $self->initialize;
  return $self;
}

sub initialize {
  my $self = shift;

  $self->{source} = $self->schema->source($self->name);

  return;
}

sub name   { $_[0]{name}   }
sub runner { $_[0]{runner} }
sub source { $_[0]{source} }

sub schema { $_[0]->runner->schema }

# Delegate the following methods:
# * relationships
# * relationship_info (Consider melding the two)

1;
__END__
