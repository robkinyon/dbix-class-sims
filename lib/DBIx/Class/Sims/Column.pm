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

  $self->{is_in_pk} = 0;
  $self->{uks} = [];
  $self->{fks} = [];

  return;
}

sub info   { shift->{info} }
sub name   { shift->{name} }
#sub source { shift->{source} }

sub is_nullable { shift->info->{is_nullable} }
sub is_auto_increment { shift->info->{is_auto_increment} }
sub is_inflated { shift->info->{_inflate_info} }

sub has_default_value { exists shift->{info}{default_value} }
#sub default_value {}

sub is_in_pk { shift->{is_in_pk} }
sub in_pk { shift->{is_in_pk} = 1; return }

sub is_in_uk { @{shift->{uks}} != 0 }
sub in_uk { push @{shift->{uks}}, $_[0]; return }

sub is_in_fk { @{shift->{fks}} != 0 }
sub in_fk { push @{shift->{fks}}, $_[0]; return }

#sub sim_spec {}
my %types = (
  numeric => {( map { $_ => 1 } qw(
    tinyint smallint mediumint bigint
    int integer int1 int2 int3 int4 int8 middleint
    bool boolean
  ))},
  decimal => {( map { $_ => 1 } qw(
    float float4 float8
    real
    double
    decimal dec
    numeric
    fixed
  ))},
  string => {( map { $_ => 1 } qw(
    char varchar varchar2
    binary varbinary
    text tinytext mediumtext longtext long
    blob tinyblob mediumblob longblob
  ))},
  # These will be unhandled
  #datetime => [qw(
  #  date
  #  datetime
  #  timestamp
  #  year
  #)],
  #unknown => [qw(
  #  enum set bit json
  #  geometry point linestring polygon
  #  multipoint multilinestring multipolygon geometrycollection
  #)],
);

sub is_numeric {
  my $self = shift;
  return exists $types{numeric}{$self->info->{data_type}};
}
sub is_decimal {
  my $self = shift;
  return exists $types{decimal}{$self->info->{data_type}};
}
sub is_string {
  my $self = shift;
  return exists $types{string}{$self->info->{data_type}};
}

1;
__END__
