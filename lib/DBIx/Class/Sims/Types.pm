package # Hide from PAUSE indexer
  DBIx::Class::Sims::Types;

use DBIx::Class::Sims;
DBIx::Class::Sims->set_sim_type(
  us_zipcode => \&us_zipcode,
);

use String::Random qw( random_regex );

sub us_zipcode {
  my ($info) = @_;

  my $datatype = $info->{data_type};
  if ( $datatype eq 'varchar' || $datatype eq 'char' ) {
    my $length = $info->{size} || 9;
    if ( $length < 5 ) {
      return '';
    }
    elsif ( $length < 9 ) {
      return random_regex('\d{5}');
    }
    elsif ( $length == 9 ) {
      return random_regex('\d{9}');
    }
    else {
      return random_regex('\d{5}-\d{4}');
    }
  }
  # Treat it as an int.
  else {
    return int(rand(99999));
  }
}

1;
__END__
