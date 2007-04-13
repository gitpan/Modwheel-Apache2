package Modwheel::Apache2;
use mod_perl2 2.0;
use 5.00800;
use strict;

our $VERSION = 0.01;

use Modwheel				();
use Modwheel::DB 			();
use Modwheel::User			();
use Modwheel::Object		();
use Modwheel::Template		();
use Modwheel::Repository	();
use Apache2::Access			();
use Apache2::RequestRec 	();
use Apache2::RequestUtil 	();
use Apache2::RequestIO		();
use Apache2::Const			-compile => qw(OK SERVER_ERROR FORBIDDEN NOT_FOUND DECLINED);
use Apache2::Request		();
use Apache2::Upload			();

our $MAX_UPLOAD_LIMIT = 10_485_760 ;

sub handler
{
	my $r = shift;
	return Apache2::Const::DECLINED if dont_want_this($r);

	# Don't process header requests.
	return Apache2::Const::OK		if $r->header_only;

	my $disable_uploads = $r->dir_config('ModwheelFileUploads') =~ /yes/i ? 0 : 1;
	my $req = Apache2::Request->new($r,
		#POST_MAX => "10M",
		MAX_BODY => $MAX_UPLOAD_LIMIT,
		DISABLE_UPLOADS => $disable_uploads
	);

	my $modwheel_config = {
		prefix			=> $r->dir_config('ModwheelPrefix'),
		configfile		=> $r->dir_config('ModwheelConfigFile'),
		site			=> $r->dir_config('ModwheelSite'),
		configcachetype => $r->dir_config('ConfigCacheType'),
		locale			=> $r->dir_config('Locale'),
		apache			=> $r,
		logmode			=> 'apache'
	};

	my $modwheel = Modwheel->new(%$modwheel_config);

	my $db       = Modwheel::DB->new(
		modwheel => $modwheel,
	);
	my $user     = Modwheel::User->new(
		modwheel => $modwheel,
		db		 => $db
	);
	my $object	 = Modwheel::Object->new(
		modwheel => $modwheel,
		db 		 => $db,
		user 	 => $user
	);
	my $repository = Modwheel::Repository->new(
		modwheel => $modwheel,
		db		 => $db,
		user	 => $user
	);
	my $template = Modwheel::Template->new(
		modwheel => $modwheel,
		db		 => $db,
		user	 => $user,
		object   => $object,
		repository => $repository
	);

    my $no_connect = $r->dir_config('NoDatabaseConnect');
	if ($no_connect && $no_connect ne 'Yes') {
		$db->connect() or return 500; #Apache2::Const::SERVER_ERROR
	}

	my $uname = $r->user;
	$uname ||= 'guest';
	$user->set_uname($uname);
	$user->set_uid($user->uidbyname($uname)) if $db->connected;

	my $page = $r->uri;
	my $loc  = quotemeta $r->location;
	my($parent, $left);
	my $useWebPath = $r->dir_config('ModwheelWebPathToId');
	if ($useWebPath && $useWebPath =~ /yes/i && $db->connected) {
		$parent = $req->param('parent');
		if ($parent) {
			$page =~ s/^$loc\/?//; # remove location part of uri requested.
		}
        else {
			($parent, $left) = $object->webpath_to_id($page);
		
			unless ($parent) {
				$db->disconnect();
				return Apache2::Const::NOT_FOUND
			}
		}
		$page =~ s#^.*/##;
		undef $page unless $page =~ /\.[\w\d_]+$/;
	}
	else {
		$parent = $req->param('parent');
		$page =~ s/^$loc\/?//; # remove location part of uri requested.
	}	
	$parent ||= Modwheel::Object::MW_TREE_ROOT;
	
	if ($r->dir_config('ModwheelFollowTemplates')) {
		my $o = $object->fetch({id => $parent});
		$page = $o->template if $o->template;
	}
	$page   ||= $modwheel->siteconfig->{directoryindex};

	$page =~ s#^/##; # remove leading slash.
	$page = $modwheel->siteconfig->{templatedir} . '/' . $page;
	return Apache2::Const::NOT_FOUND unless -f $page;
			

	# If the user uploads files, add them to the repository.
	my @uploads;
	if (! $disable_uploads && $db->connected) {
		foreach ($req->upload) {
			my $upload = $req->upload($_);
			if ($upload) {
				my $upload_in = $req->param('id');
				$upload_in ||= $parent;
				my %current_upload = (
					filename => $upload->filename,
					mimetype => $upload->type,
					size     => $upload->size,
					parent	 => $upload_in
				);
				$repository->upload($upload->fh, %current_upload);
				push(@uploads, \%current_upload);
			}
		}
	}
	# set up the template object:
	$template->init(input => $page, param => $req, parent => $parent)
		or return printError($template->errstr);

	my $content_type = $r->dir_config('ContentType') || 'text/html';
	$r->content_type($content_type);

	my $process_args = { };
	my $output = $template->process($process_args);
	

	$r->print($output);

	# ## caveman debugging goes here: :-)
	#$r->print('<html><head><title>a</title><body>');
	#$r->print('<h1>', $page, '</h1>');
	#$r->print('</body></html>');
	
	$db->disconnect() if $db->connected;

	return Apache2::Const::OK;

}

sub printError
{
	my($r, $errstr) = @_;
	$r->content_type('text/html');
	print '<html><head><title>Modwheel - Error</title></head><body>';
	print '<h1>Sorry! An error occured.</h1>';
	print '<h3>The error was:</h3>';
	print '<p>'. $errstr. '</p>';
	print '</body></html>';
	return Apache2::Const::OK;
}

sub dont_want_this
{
	my $r = shift;
	return 1 if $r->uri =~ /favicon\.ico$/;
	my $dontHandle = $r->dir_config('DontHandle');
	if($dontHandle)
	{
		foreach(split( /\s+/, $dontHandle))
		{
            s#^/##; # remove trailing slashes.
			if($r->uri =~ m#^/\Q$_\E#)
			{
				return 1
			}
		}
	}
	return 0;
}

1;
__END__

=head1 NAME

Modwheel::Apache2 - Use Modwheel with mod_perl2

=head1 SYNOPSIS

	<VirtualHost *:80>
   		 ServerName admin.localhost
	    ErrorLog logs/error_log
	    <Location />
	        SetHandler perl-script                                                                                                             
	        PerlAuthenHandler   Modwheel::Apache2::Authen                                                                                     
	        PerlResponseHandler Modwheel::Apache2                                                                                             
	        PerlSetVar ModwheelPrefix       /opt/devel/Modwheel                                                                               
	        PerlSetVar ModwheelConfigFile   config/modwheelconfig.yml                                                                         
	        PerlSetVar ModwheelSite         Admin                                                                                             
	        PerlSetVar ModwheelFileUploads  Yes                                                                                               
	        PerlSetVar Locale               en_EN                                                                                             
	        PerlSetVar DontHandle           "rep javascript css images scriptaculous"                                                         
                                                                                                                                          
	        AuthType Basic                                                                                                                    
	        AuthName "void"                                                                                                                   
	        Require valid-user                                                                                                                
	    </Location>                                                                                                                           
	    Alias /rep /opt/devel/Modwheel/Repository                                                                                             
	    Alias /css /opt/devel/Modwheel/Templates/SimpleAdmin/css                                                                              
	    Alias /javascript /opt/devel/Modwheel/Templates/SimpleAdmin/javascript                                                                
	    Alias /scriptaculous /opt/devel/Modwheel/Templates/Scriptaculous                                                                      
	    <Directory /opt/devel/Modwheel/Repository/*/*>                                                                                        
	        Order Deny,Allow                                                                                                                  
	        Allow from all                                                                                                                    
	    </Directory>                                                                                                                          
	    <Directory /opt/devel/Modwheel/Templates/*/*>                                                                                         
	        Order Deny,Allow                                                                                                                  
	        Allow from all                                                                                                                    
	    </Directory>                                                                                                                          
	</VirtualHost>	

=head1 EXPORT

None.

=head1 HISTORY

=over 8

=item 0.01

Initial version.

=back

=head1 SEE ALSO

The README included in the Modwheel distribution.

The Modwheel website: http://www.0x61736b.net/Modwheel/


=head1 AUTHORS

Ask Solem Hoel, F<< ask@0x61736b.net >>.

=head1 COPYRIGHT, LICENSE

Copyright (C) 2007 by Ask Solem Hoel C<< ask@0x61736b.net >>.

All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.6 or,
at your option, any later version of Perl 5 you may have available.

=cut

# Local variables:
# vim: ts=4
