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

sub meta   { shift->spec->{__META__} }
sub runner { shift->source->runner }
sub schema { shift->source->schema }
sub source_name { shift->source->name }

sub allow_pk_set_value { shift->meta->{allow_pk_set_value} }
sub set_allow_pk_to {
  my $self = shift;
  my ($proto) = @_;

  if (blessed($proto)) {
    $self->meta->{allow_pk_set_value} = $proto->meta->{allow_pk_set_value};
  }
  else {
    $self->meta->{allow_pk_set_value} = $proto;
  }

  return;
}

sub row {
  my $self = shift;
  $self->{row} = shift if @_;
  return $self->{row};
}

# Delegate the following methods. This will be easier with Moose.
sub relationships { shift->source->relationships(@_) }
sub relationship_info { shift->source->relationship_info(@_) }

1;
__END__
