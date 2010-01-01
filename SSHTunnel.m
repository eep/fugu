/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SSHTunnel.h"
#import "SSHTunnelAuth.h"
#import "NSString(SSHAdditions).h"
#import "NSWorkspace(LaunchServices).h"
#import "UMKeychain.h"

#include <sys/types.h>
#include <sys/param.h>
#include <netdb.h>
#include <unistd.h>

extern int		mfd;

@implementation SSHTunnel

- ( id )init
{
    NSPort		*recPort;
    NSPort		*sendPort;
    NSArray		*portArray;
    
    /* prepare distributed objects for scp task thread, but don't establish connection yet */
    recPort = [ NSPort port ];
    sendPort = [ NSPort port ];
    connectionToTServer = [[ NSConnection alloc ] initWithReceivePort: recPort
                                                sendPort: sendPort ];
    [ connectionToTServer setRootObject: self ];
    ssh = nil;
    portArray = [ NSArray arrayWithObjects: sendPort, recPort, nil ];
    [ NSThread detachNewThreadSelector: @selector( connectWithPorts: )
                                        toTarget: [ SSHTunnelAuth class ]
                                        withObject: portArray ];
                                            
    return (( self = [ super init ] ) ? self : nil );
}

- ( void )setServer: ( id )serverObject
{
    [ serverObject setProtocolForProxy: @protocol( SSHTunnelAuthInterface ) ];
    [ serverObject retain ];
    
    ssh = ( SSHTunnelAuth <SSHTunnelAuthInterface> * )serverObject;
}

- ( void )displayWindow//ForLocalPort: ( int )port
{
    NSUserDefaults	*defaults;
    NSArray		*thosts, *favs;
    NSString		*defhost = nil, *defuser = nil;
    int			i;

    [ self setFirstPasswordPrompt: YES ];
    [ self setGotPasswordFromKeychain: NO ];
    [ connectProgBar retain ];
    [ connectProgBar removeFromSuperview ];
    [ connectMsg retain ];
    [ connectMsg removeFromSuperview ];
    [ sshtunnelSheet setContentView: tunnelCreationView ];
    defaults = [ NSUserDefaults standardUserDefaults ];
    thosts = [ defaults objectForKey: @"tunneledhosts" ];
    defhost = [ defaults objectForKey: @"defaulthost" ];
    favs = [ defaults objectForKey: @"Favorites" ];
    
    /*
     * since I was foolish and made favorites in
     * early releases just NSStrings, we have to extract the
     * relevant information depending on the type of favorite
     * we're dealing with.
     */
    for ( i = 0; i < [ favs count ]; i++ ) {
        id			favobj = nil;
        NSAutoreleasePool	*p = [[ NSAutoreleasePool alloc ] init ];
        
        if ( [[ favs objectAtIndex: i ] isKindOfClass: [ NSDictionary class ]] ) {
            favobj = [[ favs objectAtIndex: i ] objectForKey: @"host" ];
        } else if ( [[ favs objectAtIndex: i ] isKindOfClass: [ NSString class ]] ) {
            favobj = [ favs objectAtIndex: i ];
        } else {
            continue;
        }
        [ tunnelHostField addItemWithObjectValue: favobj ];
        [ p release ];
    }

    if ( defhost == nil || [ defhost isEqualToString: @"" ] ) {
	if ( [ favs count ] > 0 ) {
	    id			item = [ favs objectAtIndex: 0 ];
	    
	    if ( [ item isKindOfClass: [ NSDictionary class ]] ) {
		defhost = [ item objectForKey: @"host" ];
		
		if (( defuser = [ item objectForKey: @"user" ] ) != nil ) {
		    [ usernameField setStringValue: defuser ];
		}
		if ( [ item objectForKey: @"port" ] != nil ) {
		    [ tunnelPortField setStringValue: [ item objectForKey: @"port" ]];
		}
	    } else if ( [ item isKindOfClass: [ NSString class ]] ) {
		defhost = ( NSString * )item;
	    }
	    [ tunnelHostField setStringValue: defhost ];
	}
    }
    if ( thosts != nil ) {
	[ remoteHostField addItemsWithObjectValues: thosts ];
	[ remoteHostField setNumberOfVisibleItems: [ remoteHostField numberOfItems ]];
    }
    
    [ sshtunnelSheet setTitle:
            NSLocalizedStringFromTable( @"Create SSH Tunnel",
                @"SSHTunnel", @"Create SSH Tunnel" ) ];
    [ passErrorField setStringValue: @"" ];
    //[ self reloadServiceFavorites ];
    [ sshtunnelSheet makeKeyAndOrderFront: nil ];
}

- ( void )getContinueQueryWithString: ( NSString * )string
{
    NSDictionary	*dict;
    
    dict = [ NSString unknownHostInfoFromString: string ];
    
    [ unknownHostMsgField setStringValue: [ dict objectForKey: @"msg" ]];
    [ unknownHostMsgField setEditable: NO ];
    [ unknownHostKeyField setStringValue: [ dict objectForKey: @"key" ]];
    [ unknownHostKeyField setEditable: NO ];
    
    [ sshtunnelSheet setContentView: unknownHostView ];
}

- ( BOOL )firstPasswordPrompt
{
    return( _firstPasswordPrompt );
}

- ( void )setFirstPasswordPrompt: ( BOOL )fp
{
    _firstPasswordPrompt = fp;
}

- ( BOOL )gotPasswordFromKeychain
{
    return( _gotPasswordFromKeychain );
}

- ( void )setGotPasswordFromKeychain: ( BOOL )gp
{
    _gotPasswordFromKeychain = gp;
}

- ( void )authenticateWithPrompt: ( char * )prompt
{
    NSString		*password;
    OSStatus		err;
    
    [ connectProgBar stopAnimation: nil ];
    [ authProgBar stopAnimation: nil ];
    [ authProgBar retain ];
    [ authProgBar removeFromSuperview ];
    [ authProgMsg retain ];
    [ authProgMsg removeFromSuperview ];
    
    if ( [ self firstPasswordPrompt ] ) {
        password = [[ UMKeychain defaultKeychain ]
			passwordForService: [ tunnelHostField stringValue ]
			account: [ usernameField stringValue ]
			keychainItem: NULL error: &err ];
	if ( password != nil ) {
	    [ self setGotPasswordFromKeychain: YES ];
	    [ self write: ( char * )[ password UTF8String ]];
	    return;
	}
	/* XXX handle error */
    }
    
    [ sshtunnelSheet setContentView: passpromptView ];
    [ passPromptField setStringValue: [ NSString stringWithUTF8String: prompt ]];
    [ passwordField selectText: nil ];
}

- ( void )write: ( char * )buf
{
    int		wr;
    
    if (( wr = write( mfd, buf, strlen( buf ))) != strlen( buf )) goto WRITE_ERR;
    if (( wr = write( mfd, "\n", strlen( "\n" ))) != strlen( "\n" )) goto WRITE_ERR;
    
    return;
    
WRITE_ERR:
    NSRunAlertPanel( NSLocalizedString( @"Write failed: Did not write correct number of bytes!",
                                        @"Write failed: Did not write correct number of bytes!" ),
        NSLocalizedString( @"Wrote %d bytes to file descriptor",
                            @"Wrote %d bytes to file descriptor" ),
        NSLocalizedString( @"Exit", @"Exit" ), @"", @"", wr );
    exit( 2 );
}

- ( void )addPasswordToKeychain
{
    NSString		*password;
    SecKeychainItemRef	kcItem;
    OSStatus		err;
    
    err = [[ UMKeychain defaultKeychain ]
			storePassword: [ passwordField stringValue ]
			forService: [ tunnelHostField stringValue ]
			account: [ usernameField stringValue ]
			keychainItem: NULL ];
    switch ( err ) {
    case 0:
	break;
	
    case errSecDuplicateItem:
	password = [[ UMKeychain defaultKeychain ]
			passwordForService: [ tunnelHostField stringValue ]
			account: [ usernameField stringValue ]
			keychainItem: &kcItem error: &err ];
			
	if ( password != nil ) {
	    NSLog( @"Keychain item already exists, replacing..." );
	    [[ UMKeychain defaultKeychain ]
			    changePassword: [ passwordField stringValue ]
			    forKeychainItem: kcItem ];
	    CFRelease( kcItem );
	    [ self setFirstPasswordPrompt: YES ];
	}
	break;
	
    default:
	/* XXX report error */
	break;
    }
}

- ( IBAction )authenticate: ( id )sender
{
    char	pass[ NAME_MAX ] = { 0 };
    
    [ passpromptView addSubview: authProgMsg ];
    [ passpromptView addSubview: authProgBar ];
    [ authProgBar setUsesThreadedAnimation: YES ];
    [ authProgBar startAnimation: nil ];

    bcopy( [[ passwordField stringValue ] UTF8String ], pass,
            strlen( [[ passwordField stringValue ] UTF8String ] ));
    if ( [ addToKeychainSwitch state ] == NSOnState ) {
        [ self addPasswordToKeychain ];
    }
    [ self write: pass ];
    [ passwordField setStringValue: @"" ];
}

- ( void )passError
{
    if ( [ self firstPasswordPrompt ] && [ self gotPasswordFromKeychain ] ) {
	[ passErrorField setStringValue:
		NSLocalizedString( @"Keychain password incorrect.",
				   @"Keychain password incorrect." ) ];
    } else {
	[ passErrorField setStringValue:
		NSLocalizedString( @"Permission denied. Try again.",
				   @"Permission denied. Try again." ) ];
    }
    
    [ self setFirstPasswordPrompt: NO ];
    [ addToKeychainSwitch setState: NSOffState ];
}

- ( void )connectionError: ( NSString * )errmsg
{
    NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ), errmsg,
                    NSLocalizedString( @"OK", @"OK" ), @"", @"" );
    [ sshtunnelSheet close ];
}

- ( IBAction )acceptHost: ( id )sender
{
    [ self write: "yes" ];
}

- ( IBAction )refuseHost: ( id )sender
{
    [ self write: "no" ];
}

- ( IBAction )cancelTunnelCreation: ( id )sender
{
    if ( sshpid > 0 ) {
NSLog( @"%d", sshpid );
        if ( kill( sshpid, SIGTERM ) < 0 ) {
            NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
                @"kill %d: %s", NSLocalizedString( @"OK", @"OK" ),
                @"", @"", sshpid, strerror( errno ));
            return;
        }
    }
    [ sshtunnelSheet close ];
}

- ( void )setSSHPID: ( pid_t )pid
{
    sshpid = pid;
}

- ( IBAction )closeTunnel: ( id )sender
{
    int			rc;
    
    rc = NSRunAlertPanel( NSLocalizedStringFromTable(
                            @"Are you sure you want to close this tunnel?", @"SSHTunnel",
                            @"Are you sure you want to close this tunnel?" ),
            [ NSString stringWithFormat: NSLocalizedStringFromTable(
                            @"The tunnel to port %@ of host %@ will be destroyed.", @"SSHTunnel",
                            @"The tunnel to port %@ of host %@ will be destroyed." ),
                [ remotePortField stringValue ], [ remoteHostField stringValue ]],
            NSLocalizedStringFromTable( @"Close Tunnel", @"SSHTunnel", @"Close Tunnel" ),
            NSLocalizedString( @"Cancel", @"Cancel" ), @"" );
            
    switch ( rc ) {
    case NSAlertDefaultReturn:
        break;
        
    default:
    case NSAlertAlternateReturn:
        return;
    }

    if ( sshpid > 0 ) {
        if ( kill( sshpid, SIGTERM ) < 0 ) {
            NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
                @"kill %d: %s", NSLocalizedString( @"OK", @"OK" ),
                @"", @"", sshpid, strerror( errno ));
            return;
        }
    }
    [ sshtunnelWindow close ];
    [ self setFirstPasswordPrompt: YES ];
    [ self setGotPasswordFromKeychain: NO ];
}

- ( IBAction )startTunnel: ( id )sender
{
    char		*tport, *servname, portstring[ MAXPATHLEN ];
    char		*localport = NULL;
    unsigned int	port;
    struct servent	*se;
    
    if ( ![[ remoteHostField stringValue ] length ]
            || ![[ remotePortField stringValue ] length ]
            || ![[ tunnelHostField stringValue ] length ]
            || ![[ usernameField stringValue ] length ] ) {
        NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
            NSLocalizedStringFromTable( @"You must fill in all fields. Please try again.",
                    @"SSHTunnel", @"You must fill in all fields. Please try again." ),
            NSLocalizedString( @"OK", @"OK" ), @"", @"" );
        return;
    }
    
    servname = ( char * )[[ remotePortField stringValue ] UTF8String ];
    if (( se = getservbyname( servname, "tcp" )) == NULL ) {
	if (( port = [ remotePortField intValue ] ) == 0 ) {
	    NSBeginAlertSheet( NSLocalizedString( @"Error", @"Error" ),
		NSLocalizedString( @"OK", @"OK" ), @"", @"", sshtunnelSheet, self,
		NULL, NULL, NULL,
                NSLocalizedStringFromTable( @"You must fill in all fields. Please try again.",
                    @"SSHTunnel", @"You must fill in all fields. Please try again." ));
	    return;
	}
    } else {
	port = se->s_port;
    }
	
    if ( snprintf( portstring, MAXPATHLEN, "%u", port ) > ( MAXPATHLEN - 1 )) {
	NSLog( @"%u: string exceeds bounds.", port );
	return;
    }

    [ sender setEnabled: NO ];
    [ tunnelCreationView addSubview: connectProgBar ];
    [ connectProgBar setUsesThreadedAnimation: YES ];
    [ connectProgBar startAnimation: nil ];
    [ tunnelCreationView addSubview: connectMsg ];
    [ remotePortField setStringValue: [ NSString stringWithFormat: @"%u", port ]];
    
    if ( ! [ tunnelPortField intValue ] ) {
        tport = "22";
    } else {
        tport = ( char * )[[ tunnelPortField stringValue ] UTF8String ];
    }
    
    if ( ! [ localPortField intValue ] || [ localPortField intValue ] < 1024 ) {
        localport = "1024";
        [ localPortField setStringValue: @"1024" ];
    } else {
        localport = ( char * )[[ localPortField stringValue ] UTF8String ];
    }
    
    [ ssh sshTunnelLocalPort: localport
            remoteHost: ( char * )[[ remoteHostField stringValue ] UTF8String ]
            remotePort: portstring
            tunnelUserAndHost: ( char * )[[ NSString stringWithFormat: @"%@@%@",
                                            [ usernameField stringValue ],
                                            [ tunnelHostField stringValue ]] UTF8String ]
            tunnelPort: tport
            fromController: self ];
    [ self addTunneledHostToDefaults: [ remoteHostField stringValue ]];
}

- ( void )addTunneledHostToDefaults: ( NSString * )rHost
{
    NSUserDefaults		*defaults = [ NSUserDefaults standardUserDefaults ];
    NSArray			*oldts = [ defaults objectForKey: @"tunneledhosts" ];
    NSMutableArray		*newts;
    int				i, found = 0;
    
    if ( oldts == nil ) {
        [ defaults setObject: [ NSArray arrayWithObject: rHost ] forKey: @"tunneledhosts" ];
        [ defaults synchronize ];
        return;
    }
    
    newts = [[ NSMutableArray alloc ] init ];
    [ newts addObjectsFromArray: oldts ];
    for ( i = 0; i < [ oldts count ]; i++ ) {
        if ( [ rHost isEqualToString: [ oldts objectAtIndex: i ]] ) { found++; break; }
    }
    
    if ( !found ) [ newts insertObject: rHost atIndex: 0 ];
    
    while ( [ newts count ] > 10 ) {
        [ newts removeLastObject ];
    }
    
    [ defaults setObject: newts forKey: @"tunneledhosts" ];
    [ defaults synchronize ];
    [ newts release ];
}

- ( void )tunnelCreated
{
    [ sshtunnelSheet close ];
    [ sshtunnelWindow setTitle: [ NSString stringWithFormat:
            NSLocalizedStringFromTable( @"Tunnel: local port %@ to port %@ of %@",
                @"SSHTunnel", @"Tunnel: local port %@ to port %@ of %@" ),
                [ localPortField stringValue ], [ remotePortField stringValue ],
                [ remoteHostField stringValue ]]];
            
    [ sshTunnelInfoButton removeAllItems ];
    [ sshTunnelInfoButton addItemsWithTitles:
        [ NSArray arrayWithObjects:
                NSLocalizedStringFromTable( @"Tunnel Information", @"SSHTunnel",
                                            @"Tunnel Information" ),
                [ NSString stringWithFormat:
                    NSLocalizedStringFromTable( @"Local Port: %@", @"SSHTunnel",
                                                @"Local Port: %@" ),
                                                [ localPortField stringValue ]],
                [ NSString stringWithFormat:
                    NSLocalizedStringFromTable( @"Remote Host: %@", @"SSHTunnel",
                                        @"Remote Host: %@" ), [ remoteHostField stringValue ]],
                [ NSString stringWithFormat:
                    NSLocalizedStringFromTable( @"Remote Port: %@", @"SSHTunnel",
                                        @"Remote Port: %@" ), [ remotePortField stringValue ]],
                [ NSString stringWithFormat:
                    NSLocalizedStringFromTable( @"Tunnel Host: %@", @"SSHTunnel",
                                        @"Tunnel Host: %@" ), [ tunnelHostField stringValue ]],
                nil ]];
    [ sshtunnelWindow makeKeyAndOrderFront: nil ];
}

@end
