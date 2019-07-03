# This class exists to represent a row requested (and subsequently created) by
# the Sims. It will have a link back to a Sims::Source which will have the link
# back to the $schema object.

package DBIx::Class::Sims::Item;

use 5.010_001;

use strictures 2;

sub new {
  my $class = shift;
  my $self = bless {@_}, $class;
  $self->initialize;
  return $self;
}

sub initialize {
  my $self = shift;

  $self->{original} = MyCloner::clone($self->{spec});

  return;
}

sub runner { $_[0]{runner} }
sub source { $_[0]{source} }
sub schema { $_[0]->source->schema }

sub spec { $_[0]{spec} }

#sub allow_pk_set_value {
#  my $self = shift;
#
#  return $self->{allow_pk_set_value} || $self->runner->allow_pk_set_value;
#}

1;
__END__
