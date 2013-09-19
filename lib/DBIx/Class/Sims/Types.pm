package # Hide from PAUSE indexer
  DBIx::Class::Sims::Types;

use DBIx::Class::Sims;
DBIx::Class::Sims->set_sim_type(
  us_zipcode => \&us_zipcode,
  us_state => \&us_state,
  us_phone => \&us_phone,
);

use String::Random qw( random_regex );

sub us_phone {
  my ($info) = @_;

  # Assume a varchar-like column type.
  my $length = $info->{size} || 8;
  if ( $length < 7 ) {
    return '';
  }
  elsif ( $length == 7 ) {
    return random_regex('\d{7}');
  }
  elsif ( $length < 10 ) {
    return random_regex('\d{3}-\d{4}');
  }
  elsif ( $length < 12 ) {
    return random_regex('\d{10}');
  }
  elsif ( $length == 12 ) {
    return random_regex('\d{3}-\d{3}-\d{4}');
  }
  # random_regex() throws a warning no matter how I try to specify the parens.
  # It does the right thing, but noisily. So, just concatenate them.
  elsif ( $length == 13 ) {
    return '(' . random_regex('\d{3}') . ')' . random_regex('\d{3}-\d{4}');
  }
  elsif ( $length >= 14 ) {
    return '(' . random_regex('\d{3}') . ') ' . random_regex('\d{3}-\d{4}');
  }
}

my @states = (
  [ AL => 'Alabama' ],
  [ AK => 'Alaska' ],
  [ AZ => 'Arizona' ],
  [ AR => 'Arkansas' ],
  [ CA => 'California' ],
  [ CO => 'Colorado' ],
  [ CT => 'Connecticut' ],
  [ DE => 'Delaware' ],
  [ FL => 'Florida' ],
  [ GA => 'Georgia' ],
  [ HI => 'Hawaii' ],
  [ ID => 'Idaho' ],
  [ IL => 'Illinois' ],
  [ IN => 'Indiana' ],
  [ IA => 'Iowa' ],
  [ KS => 'Kansas' ],
  [ KY => 'Kentucky' ],
  [ LA => 'Louisiana' ],
  [ ME => 'Maine' ],
  [ MD => 'Maryland' ],
  [ MA => 'Massachusetts' ],
  [ MI => 'Michigan' ],
  [ MN => 'Minnesota' ],
  [ MS => 'Mississippi' ],
  [ MO => 'Missouri' ],
  [ MT => 'Montana' ],
  [ NE => 'Nebraska' ],
  [ NJ => 'New Jersey' ],
  [ NH => 'New Hampshire' ],
  [ NV => 'Nevada' ],
  [ NM => 'New Mexico' ],
  [ NY => 'New York' ],
  [ NC => 'North Carolina' ],
  [ ND => 'North Dakota' ],
  [ OH => 'Ohio' ],
  [ OK => 'Oklahoma' ],
  [ OR => 'Oregon' ],
  [ PA => 'Pennsylvania' ],
  [ RI => 'Rhode Island' ],
  [ SC => 'South Carolina' ],
  [ SD => 'South Dakota' ],
  [ TN => 'Tennessee' ],
  [ TX => 'Texas' ],
  [ UT => 'Utah' ],
  [ VT => 'Vermont' ],
  [ VA => 'Virginia' ],
  [ WA => 'Washington' ],
  [ WV => 'West Virginia' ],
  [ WI => 'Wisconsin' ],
  [ WY => 'Wyoming' ],
  # These are territories, not states, but that's okay.
  [ AS => 'American Samoa' ],
  [ DC => 'District Of Columbia' ],
  [ GU => 'Guam' ],
  [ MD => 'Midway Islands' ],
  [ NI => 'Northern Mariana Islands' ],
  [ PR => 'Puerto Rico' ],
  [ VI => 'Virgin Islands' ],
);
sub us_state {
  my ($info) = @_;

  # Assume a varchar-like column type.
  my $length = $info->{size} || 2;
  if ( $length == 2 ) {
    return $states[rand @states][0];
  }
  return substr($states[rand @states][1], 0, $length);
}

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
