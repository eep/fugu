/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SSHTunnelAuth.h"
#import "SSHTunnel.h"
#import "NSString(SSHAdditions).h"

#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/param.h>
#include <sys/wait.h>
#include <sys/time.h>
#include <util.h>

#include "argcargv.h"

extern int	errno;

@implementation SSHTunnelAuth

extern char	**environ;

int		sshconnecting = 0;
int		mfd = 0;

+ ( void )connectWithPorts: ( NSArray * )ports
{
    NSAutoreleasePool		*pool = [[ NSAutoreleasePool alloc ] init ];
    NSConnection		*cnctnToController;
    SSHTunnelAuth		*serverObject;
    
    cnctnToController = [ NSConnection connectionWithReceivePort:
                            [ ports objectAtIndex: 0 ]
                            sendPort: [ ports objectAtIndex: 1 ]];
                            
    serverObject = [[ self alloc ] init ];
    
    [ (( SSHTunnel * )[ cnctnToController rootProxy ] ) setServer: serverObject ];
    [ serverObject release ];
    
    [[ NSRunLoop currentRunLoop ] run ];
    
    [ pool release ];
}

- ( id )init
{
    sshpid = 0;
    return(( self = [ super init ] ) ? self : nil );
}

- ( int )closeMasterFD
{
    if ( close( mfd ) < 0 ) {
        return( -1 );
    }
    
    return( 0 );
}

- ( oneway void )sshTunnelLocalPort: ( char * )lport remoteHost: ( char * )rhost
                remotePort: ( char * )rport tunnelUserAndHost: ( char * )userathost
                tunnelPort:  ( char * )tport
                fromController: ( SSHTunnel * )controller
{
    fd_set		readmask;
    FILE		*mfp;
    int			status, pwsent = 0, validpw = 0, threestrikes = 0;
    char		*unknownmsg;
    char		ttyname[ MAXPATHLEN ], buf[ MAXPATHLEN ], tportarg[ MAXPATHLEN ];
    char		executable[ MAXPATHLEN], portarg[ MAXPATHLEN ], *execargs[ 7 ];
    NSString    	*sshBinary;
    
    if (( sshBinary = [ NSString pathForExecutable: @"ssh" ] ) == nil ) {
	NSLog( @"Couldn't find ssh!" );
	return;
    }
    if ( [ sshBinary length ] >= MAXPATHLEN ) {
	NSLog( @"%@: path too long" );
	return;
    }
    strcpy( executable, [ sshBinary UTF8String ] );
    execargs[ 0 ] = executable;

    sshconnecting = 1;
    
    if ( snprintf( portarg, MAXPATHLEN, "-L%s:%s:%s",
		lport, rhost, rport ) >= ( MAXPATHLEN )) {
        NSLog( @"portarg exceeds bounds" );
    }
    snprintf( tportarg, MAXPATHLEN, "-oPort=%s", tport );
    
    execargs[ 1 ] = "-N";
    execargs[ 2 ] = portarg;
    execargs[ 3 ] = userathost;
    execargs[ 4 ] = tportarg;
    execargs[ 5 ] = "-v";
    execargs[ 6 ] = NULL;

    if ( sshpid = forkpty( &mfd, ttyname, NULL, NULL )) {
        if ( fcntl( mfd, F_SETFL, O_NONBLOCK ) < 0 ) {	/* prevent master from blocking */
        }
        
        [ controller setSSHPID: sshpid ];
                                    
        FD_ZERO( &readmask );
        if (( mfp = fdopen( mfd, "r" )) == NULL ) {
            NSLog( @"fdopen master fd returned NULL" );
            exit( 2 );
        }
        
        for ( ;; ) {
            NSAutoreleasePool	*pool = [[ NSAutoreleasePool alloc ] init ];
            
            FD_SET( mfd, &readmask );
            if ( select( mfd + 1, &readmask, NULL, NULL, NULL ) < 0 ) {
                NSLog( @"select() returned a value less than zero" );
                return;
            }
            
            if ( FD_ISSET( mfd, &readmask )) {
                if ( fgets( buf, MAXPATHLEN, mfp ) == NULL ) break;
                
                if (( strstr( buf, "Password:" ) != NULL
                        || strstr( buf, "password:" ) != NULL
                        || strstr( buf, "passphrase" ) != NULL )
                        && !validpw ) {
                    if ( sshconnecting ) [ controller authenticateWithPrompt: buf ];
                    pwsent = 1;
                } else {
                    if ( strncmp( buf, "Permission denied, ", strlen( "Permission denied, " )) == 0 ) {
                        [ controller passError ];
                        pwsent = 0;
                        threestrikes++;
                    } else if ( strstr( buf, "passphrase for key" ) != NULL ) {
                        pwsent = 0;
                        threestrikes = 0;	/* if pubkey auth fails, password prompt will appear */
                    } else if ( strncmp( buf, "The auth", strlen( "The auth" )) == 0 ) {
                        unknownmsg = strdup( buf );
                        fgets( buf, MAXPATHLEN, mfp );
                        [ controller getContinueQueryWithString:
                                [ NSString stringWithFormat: @"%s%s", unknownmsg, buf ]];
                        free( unknownmsg );
                    } else if ( strncmp( buf, "Secure ", strlen( "Secure" )) == 0 ) {
                        [ controller connectionError: [ NSString stringWithUTF8String: buf ]];
                    } else if ( strstr( buf, "successful: method" ) != NULL ) {
                        if ( strstr( buf, "debug" ) != NULL ) {
                            [ controller tunnelCreated ];
                        }
                    } else if ( strstr( buf, "Authentication succeeded" ) != NULL ) {
                        if ( strstr( buf, "debug" ) != NULL ) {
                            [ controller tunnelCreated ];
                        }
                    }
                }
                
                if ( strstr( buf, "Operation timed out" ) != NULL
                        || strstr( buf, "REMOTE HOST IDENTIFICATION HAS CHANGED" ) != NULL ) {
                    char		*p = strdup( buf ), *q;
                    
                    if (( q = strrchr( p, '\r' )) != NULL ) *q = '\0';
                    [ controller connectionError:
                        [ NSString stringWithUTF8String: p ]];
                    free( p );
                }

                memset( buf, '\0', strlen( buf ));
            }
            [ pool release ];
        }
        if ( threestrikes == 3 ) {
            [ controller connectionError: @"Authentication failed." ];
        }
        
        wait( &status );
        
        NSLog( @"exited with %d", WEXITSTATUS( status ));
    } else if ( sshpid < 0 ) {
        NSLog( @"forkpty failed: %s", strerror( errno ));
    } else {
        execve( executable, ( char ** )execargs, environ );
        NSLog( @"execve failed: %s", strerror( errno ));
        
        _exit( 2 );						/* shouldn't get here */
    }
}

@end
