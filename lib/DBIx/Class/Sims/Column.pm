# This class exists to encapsulate the a DBIx::Class column hashref and provide
# Sims-specific functionality to navigate columns and what goes into a column.

package DBIx::Class::Sims::Column;

use 5.010_001;

use strictures 2;

use DDP;

use String::Random qw( random_regex );

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

sub initialize {
  my $self = shift;

  $self->{is_in_pk} = 0;
  $self->{uks} = [];
  $self->{fks} = [];

  if ( exists $types{numeric}{$self->info->{data_type}} ) {
    $self->{type} = 'numeric';
  }
  elsif ( exists $types{decimal}{$self->info->{data_type}} ) {
    $self->{type} = 'decimal';
  }
  elsif ( exists $types{string}{$self->info->{data_type}} ) {
    $self->{type} = 'string';
  }
  else {
    $self->{type} = 'unknown';
  }

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
sub is_numeric { shift->{type} eq 'numeric' }
sub is_decimal { shift->{type} eq 'decimal' }
sub is_string  { shift->{type} eq 'string' }
sub is_unknown { shift->{type} eq 'unknown' }

sub generate_value {
  my $self = shift;

  if ( $self->is_numeric ) {
    my $min = 0;
    my $max = 100;
    return int(rand($max-$min))+$min;
  }
  elsif ( $self->is_decimal ) {
    my $min = 0;
    my $max = 100;
    return rand($max-$min)+$min;
  }
  elsif ( $self->is_string ) {
    my $min = 1;
    my $max = $self->info->{data_length} // $self->info->{size} // $min;
    return random_regex(
      '\w' . "{$min,$max}"
    );
  }
  else {
    die "ERROR: @{[$self->source->name]}\.@{[$self->name]} is not nullable, but I don't know how to handle @{[$self->info->{data_type}]}\n";
  }
}

1;
__END__
