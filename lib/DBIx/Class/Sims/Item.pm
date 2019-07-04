# This class exists to represent a row requested (and subsequently created) by
# the Sims. It will have a link back to a Sims::Source which will have the link
# back to the $schema object.

package DBIx::Class::Sims::Item;

use 5.010_001;

use strictures 2;

use Scalar::Util qw( blessed );

sub new {
  my $class = shift;
  my $self = bless {@_}, $class;
  $self->initialize;
  return $self;
}

sub initialize {
  my $self = shift;

  $self->spec->{__META__} //= {};

  #$self->{original} = MyCloner::clone($self->{spec});

  return;
}

sub source { $_[0]{source} }
sub spec   { $_[0]{spec}   }

sub meta   { $_[0]->spec->{__META__} }
sub runner { $_[0]->source->runner }
sub schema { $_[0]->source->schema }

sub allow_pk_set_value { $_[0]->meta->{allow_pk_set_value} }
sub set_allow_pk_to {
  my $self = shift;
  my ($proto) = @_;

  if (blessed($proto)) {
    $self->meta->{allow_pk_set_value} = $proto->meta->{allow_pk_set_value};
  }
  else {
    $self->meta->{allow_pk_set_value} = $proto;
  }
}

sub row {
  my $self = shift;
  $self->{row} = shift if @_;
  $self->{row};
}

1;
__END__
