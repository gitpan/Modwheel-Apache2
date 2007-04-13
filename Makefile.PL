use inc::Module::Install;
    
# Define metadata
name            'Modwheel-Apache2';
all_from        'lib/Modwheel/Apache2.pm';
author			'Ask Solem Hoel <ask@0x61736b.net>';
license			'perl';

    
# Specific dependencies
requires		'Modwheel'				=> 0.01;
requires		'mod_perl2'				=> 2.00;
requires        'Tie::IxHash'           => 1.21;
requires        'Parse::RecDescent'     => 1.94;
requires        'ExtUtils::XSBuilder::ParseSource' => 0.03;
requires		'Apache2::Request'		=> 2.00;
requires		'Apache2::Upload'		=> 2.00;

build_requires  'Test::More'        => 0.42;
    
#no_index        'directory'         => 'demos';
#install_script  'bin/myscript';
    
auto_install;
WriteAll;
