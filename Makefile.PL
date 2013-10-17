use 5.008_004;

use strict;
use warnings FATAL => 'all';

use inc::Module::Install 0.91;
 
perl_version '5.008_004';
all_from 'lib/DBIx/Class/Sims.pm';

requires 'Data::Walk';
requires 'DBIx::Class::TopoSort';
requires 'List::Util';
requires 'Scalar::Util';
requires 'String::Random';
requires 'YAML::XS'; # Removes a warning.
 
test_requires 'File::Temp'        => '0.01',
test_requires 'Test::DBIx::Class' => '0.01',
test_requires 'Test::Exception'   => '0.21',
test_requires 'Test::More'        => '0.88', # done_testing
test_requires 'Test::Deep'        => '0.01',
test_requires 'Test::Warn'        => '0.01',
 
WriteAll;
