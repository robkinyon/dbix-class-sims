package # Hide from PAUSE indexer
  DBIx::Class::Sims::Types;

use strict;
use warnings FATAL => 'all';

use DBIx::Class::Sims;
DBIx::Class::Sims->set_sim_types({
  map { $_ => __PACKAGE__->can($_) } qw(
    us_address us_city us_county us_name us_phone us_ssntin us_state us_zipcode
  )
});

use String::Random qw( random_regex );

{
  my @street_names = qw(
    Main Court House Mill Wood Millwood
    First Second Third Fourth Fifth Sixth Seventh Eight Ninth
    Magnolia Acacia Poppy Cherry Rose Daisy Daffodil
  );

  my @street_types = qw(
    Street Drive Place Avenue Boulevard Lane
    St Dr Pl Av Ave Blvd Ln
    St. Dr. Pl. Av. Ave. Blvd. Ln.
  );

  sub us_address {
    # Assume a varchar-like column type with enough space.

    if ( rand() < .7 ) {
      # We want to change this so that distribution is by number of digits, then
      # randomly within the numbers.
      my $number = int(rand(99999));

      my $street_name = $street_names[rand @street_names];
      my $street_type = $street_types[rand @street_types];

      return "$number $street_name $street_type";
    }
    else {
      my $po = rand() < .5 ? 'PO' : 'P.O.';
      return "$po Box " . int(rand(9999));
    }
  }
}

{
  my @city_names = qw(
    Ithaca Jonestown Marysville Ripon Minneapolis Miami Paris London Columbus
  );
  push @city_names, (
    'New York', 'Los Angeles', 'Montego By The Bay',
  );

  sub us_city {
    # Assume a varchar-like column type with enough space.
    return $city_names[rand @city_names];
  }
}

{
  my @county_names = qw(
    Adams Madison Washinton Union Clark
  );

  sub us_county {
    # Assume a varchar-like column type with enough space.
    return $county_names[rand @county_names];
  }
}

{
  my @first_names = qw(
    Aidan Bill Charles Doug Evan Frank George Hunter Ilya Jeff Kilgore
    Liam Michael Nathan Oscar Perry Robert Shawn Thomas Urkul Victor Xavier

    Alexandra Betty Camille Debra Ellen Fatima Georgette Hettie Imay Jaime
    Kathrine Leticia Margaret Nellie Ophelia Patsy Regina Sybil Tricia Valerie
  );

  my @last_names = qw(
    Jones Smith Taylor Kinyon Williams Shaner Perry Raymond Moore O'Malley
  );
  # Some last names are two words.
  push @last_names, (
    "Von Trapp", "Van Kirk",
  );

  my @suffixes = (
    'Jr', 'Sr', 'II', 'III', 'IV', 'Esq.',
  );

  sub us_name {
    # Assume a varchar-like column type with enough space.

    my @name = (
      $first_names[rand @first_names],
      $last_names[rand @last_names],
    );

    # 10% chance of adding a suffix
    if ( rand() < 0.1 ) {
      push @name, $suffixes[rand @suffixes];
    }

    return join ' ', @name;
  }
}

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

sub us_ssntin {
  # Give strong preference to a SSN
  if ( rand() < .8 ) {
    return random_regex('\d{3}-\d{2}-\d{4}');
  }
  # But still generate employer TINs to mix it up.
  else {
    return random_regex('\d{2}-\d{7}');
  }
}

{
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
