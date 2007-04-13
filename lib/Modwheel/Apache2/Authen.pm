package Modwheel::Apache2::Authen;
use mod_perl2 2.0;

use Modwheel				();
use Modwheel::DB			();
use Modwheel::User			();
use Apache2::Const			-compile => qw(OK AUTH_REQUIRED HTTP_UNAUTHORIZED DECLINED);
use Apache2::Access			();
use Apache2::Connection		();
use Apache2::RequestUtil	();
use Apache2::RequestRec		();
use Apache2::ServerRec		();
use Apache2::Log			();

sub handler
{
	my $r = shift;
	return Apache2::Const::DECLINED unless $r;

	my($res, $sent_pw) = $r->get_basic_auth_pw();
	return $res if $res != Apache2::Const::OK;

	my $uname = $r->user;
	unless($uname && $sent_pw)
	{
		$r->note_basic_auth_failure;
		$r->log_reason('Need both username and password.');
		return Apache2::Const::HTTP_UNAUTHORIZED;
	}
		
    my $modwheel_config = 
    {   
        prefix          => $r->dir_config('ModwheelPrefix'),
        configfile      => $r->dir_config('ModwheelConfigFile'),
        site            => $r->dir_config('ModwheelSite'),
        configcachetype => $r->dir_config('ConfigCacheType'),
        locale          => $r->dir_config('Locale')
    }; 	

    my $modwheel = Modwheel->new(%$modwheel_config);

    my $db       = Modwheel::DB->new(
        modwheel => $modwheel,
    );  
    my $user     = Modwheel::User->new(
        modwheel => $modwheel,
        db       => $db
    );	
	
	$db->connect or return Apache2::Const::SERVER_ERROR;
	my $server = $r->server;
	my $client = $r->connection;
	my $server_hostname = $server->server_hostname;
	my $auth_type = $r->ap_auth_type;
	my $site = $modwheel->site;
	my $remote_addr = $client->remote_ip;
	unless($user->login($uname, $sent_pw, $remote_addr))
	{
		$r->note_basic_auth_failure;
		$r->log_reason($modwheel->error);
		$db->disconnect();
		return Apache2::Const::HTTP_UNAUTHORIZED;
	}	

		
	#$r->warn("Modwheel [site: $site@$server_hostname] info || | Login: $uname [ip: $remote_addr, auth type: $auth_type]");	

	return Apache2::Const::OK;
}


1
