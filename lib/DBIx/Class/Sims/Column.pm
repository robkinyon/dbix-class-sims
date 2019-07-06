# This class exists to encapsulate the DBIx::Class::Source object and provide
# Sims-specific functionality to navigate sources and the attributes of
# sources.

package DBIx::Class::Sims::Column;

use 5.010_001;

use strictures 2;

use DDP;

# Requires the following attributes:
# * source
# * name
# * info
sub new {
  my $class = shift;
  my $self = bless {@_}, $class;
  $self->initialize;
  return $self;
}

sub initialize {
  my $self = shift;

  $self->{fks} = [];

  return;
}

sub info   { shift->{info} }
sub name   { shift->{name} }
#sub source { shift->{source} }

sub is_nullable { shift->info->{is_nullable} }
sub is_auto_increment { shift->info->{is_auto_increment} }
sub is_inflated { shift->info->{_inflate_info} }

#sub is_numeric {}
#sub is_decimal {}
#sub is_string {}

#sub has_default_value {}
#sub default_value {}

#sub is_in_pk {}
#sub is_in_uk {}

sub is_in_fk { @{shift->{fks}} != 0 }
sub in_fk { push @{shift->{fks}}, $_[0] }
#  my $self = shift;
#  my ($r) = @_;
#  push @{$self->{fks}}, $r;
#  return;
#}

#sub sim_spec {}

1;
__END__
