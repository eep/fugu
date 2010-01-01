/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SCPTransfer.h"
#import "SCPController.h"
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
#include "sshversion.h"

extern int	errno;

@implementation SCPTransfer

extern char	**environ;

int		scpconnecting = 0;

+ ( void )connectWithPorts: ( NSArray * )ports
{
    NSAutoreleasePool		*pool = [[ NSAutoreleasePool alloc ] init ];
    NSConnection		*cnctnToController;
    SCPTransfer			*serverObject;
    
    cnctnToController = [ NSConnection connectionWithReceivePort:
                            [ ports objectAtIndex: 0 ]
                            sendPort: [ ports objectAtIndex: 1 ]];
                            
    serverObject = [[ self alloc ] init ];
    
    [ (( SCPController * )[ cnctnToController rootProxy ] ) setServer: serverObject ];
    [ serverObject release ];
    
    [[ NSRunLoop currentRunLoop ] run ];
    
    [ pool release ];
}

- ( id )init
{
    scppid = 0;
    return(( self = [ super init ] ) ? self : nil );
}

- ( int )closeMasterFD
{
    if ( close( masterfd ) < 0 ) {
        return( -1 );
    }
    
    return( 0 );
}

- ( void )parseProgressOutputString: ( char * )string
            forController: ( SCPController * )controller
{
    int			tac, i, pc_index = -1;
    char		*tmp, **tav, *p;
    char		*t_rate, *t_amount, *t_eta;
    char		filename[ MAXPATHLEN ] = { 0 };
    
    if (( tmp = strdup( string )) == NULL ) {
	perror( "strdup" );
	exit( 2 );
    }
    
    if (( tac = argcargv( tmp, &tav )) < 5 ) {
	/* not a transfer progress line we're interested in */
	free( tmp );
	return;
    }
    
    for ( i = ( tac - 1 ); i >= 0; i-- ) {
	if (( p = strrchr( tav[ i ], '%' )) != NULL ) {
	    /* found the %-done field */
	    pc_index = i;
            *p = '\0';
	    break;
	}
    }
    
    /* OpenSSH 3.7 and above use a different progress output in scp */
    if ( sshversion() > 3.6 ) {
        t_amount = tav[ pc_index + 1 ];
        
        if ( pc_index == ( tac - 5 )) {
            t_eta = tav[ pc_index + 3 ];
        } else {
            t_eta = "--:--";
        }
    } else {
        int		pos;

        if ( strcmp( "ETA", tav[ tac - 1 ] ) == 0 ) {
            t_eta = tav[ tac - 2 ];
            
            if ( ! isdigit( *tav[ tac - 3 ] )) {
                pos = ( tac - 4 );
            } else {
                pos = ( tac - 3 );
            }
        } else {
            t_eta = tav[ tac - 1 ];
            if ( ! isdigit( *tav[ tac - 2 ] )) {
                pos = ( tac - 3 );
            } else {
                pos = ( tac - 2 );
            }
        }
        t_amount = tav[ pos ];
    }
    t_rate = tav[ pc_index + 2 ];
    
    /* everything before the %-done field is a filename */
    ( void )strlcpy( filename, tav[ 0 ], sizeof( filename ));
    for ( i = 1; i < pc_index; i++ ) {
        ( void )strlcat( filename, tav[ i ], sizeof( filename ));
    }
    
    [ controller fileCopying: [ NSString stringWithUTF8String: filename ]
                            updateWithPercentDone: tav[ pc_index ]
                            eta: t_eta
                            bytesCopied: t_amount ];
}

- ( oneway void )scpConnect: ( char * )userathost toPort: ( char * )portnumber
                forItem: ( char * )localfile scpType: ( int )scpType
                fromController: ( SCPController * )controller
{
    fd_set		readmask;
    FILE		*mfp;
    int			copying = 0;
    int			status, pwsent = 0, validpw = 0, threestrikes = 0, noscp = 0;
    char		*unknownmsg;
    char		ttyname[ MAXPATHLEN ];
    unichar		buf[ MAXPATHLEN ];
    char		executable[ MAXPATHLEN], portarg[ MAXPATHLEN ], *execargs[ 7 ];
    NSString		*scpBinary;
  
    [ controller clearLog ]; 

    if (( scpBinary = [ NSString pathForExecutable: @"scp" ] ) == nil ) {
	NSLog( @"Couldn't find scp!" );
	return;
    }	    
    if ( [ scpBinary length ] >= MAXPATHLEN ) {
	NSLog( @"%@: too long" );
	return;
    }
    strcpy( executable, [ scpBinary UTF8String ] );
    execargs[ 0 ] = executable;

    scpconnecting = 1;
    [ controller addToLog: [ NSString stringWithFormat: @"scp launch path is %s.\n", executable ]];
    
    if ( snprintf( portarg, MAXPATHLEN, "-oPort=%s", portnumber ) > ( MAXPATHLEN - 1 )) {
        NSLog( @"portarg exceeds bounds" );
    }
    
    execargs[ 1 ] = "-r";
    execargs[ 2 ] = "-p";
    execargs[ 3 ] = portarg;
    execargs[ 4 ] = ( scpType == 0 ? localfile : userathost );
    execargs[ 5 ] = ( scpType == 0 ? userathost : localfile );
    execargs[ 6 ] = NULL;
    
    if ( scppid = forkpty( &masterfd, ttyname, NULL, NULL )) {
        if ( fcntl( masterfd, F_SETFL, O_NONBLOCK ) < 0 ) {	/* prevent master from blocking */
        }
        
        [ controller setSCPPID: scppid ];
        [ controller setMasterFD: masterfd ];
        [ controller addToLog: [ NSString stringWithFormat: @"Slave terminal device is %s.\n",
                                ttyname ]];
        [ controller addToLog: [ NSString stringWithFormat: @"Master fd is %d.\n",
                                masterfd ]];
                                    
        if (( mfp = fdopen( masterfd, "r" )) == NULL ) {
            NSLog( @"fdopen master fd returned NULL" );
            exit( 2 );
        }
        setvbuf( mfp, NULL, _IONBF, 0 );
        
        for ( ;; ) {
            NSAutoreleasePool	*pool = [[ NSAutoreleasePool alloc ] init ];
	    FD_ZERO( &readmask );
            FD_SET( masterfd, &readmask );
            if ( select( masterfd + 1, &readmask, NULL, NULL, NULL ) < 0 ) {
                NSLog( @"select() returned a value less than zero" );
                return;
            }
            
            if ( FD_ISSET( masterfd, &readmask )) {
                if ( fgets(( char * )buf, MAXPATHLEN, mfp ) == NULL ) break;
                
                if (( strstr(( char * )buf, "Password:" ) != NULL
                        || strstr(( char * )buf, "password:" ) != NULL
                        || strstr(( char * )buf, "passphrase" ) != NULL )
                        && !validpw ) {
                    if ( scpconnecting ) [ controller authenticateWithPrompt: ( char * )buf ];
                    pwsent = 1;
                } else {
                    if ( strncmp(( char * )buf, "Permission denied, ",
                                    strlen( "Permission denied, " )) == 0 ) {
                        [ controller passError ];
                        pwsent = 0;
                        threestrikes++;
                    } else if ( strstr(( char * )buf, "passphrase for key" ) != NULL ) {
                        pwsent = 0;
                        threestrikes = 0;	/* if pubkey auth fails, password prompt will appear */
                    } else if ( strstr(( char * )buf, "scp: Command not found" ) != NULL ) {
                        [ controller sessionError: [ NSString stringWithUTF8String: ( char * )buf ]];
                        noscp++;
                    } else if ( strncmp(( char * )buf, "The auth", strlen( "The auth" )) == 0 ) {
                        unknownmsg = strdup(( char * )buf );
                        [ controller addToLog: [ NSString stringWithUTF8String: ( char * )buf ]];
                        fgets(( char * )buf, MAXPATHLEN, mfp ); /* get rest of message */
                        [ controller getContinueQueryWithString:
                                [ NSString stringWithFormat: @"%s%s", unknownmsg, ( char * )buf ]];
                        free( unknownmsg );
                    } else if ( strncmp(( char * )buf, "Secure ", strlen( "Secure" )) == 0 ) {
                        [ controller sessionError: [ NSString stringWithUTF8String: ( char * )buf ]];
                    }
                }
                if ( strchr(( char * )buf, '%' ) != NULL ) {
                    if ( ! copying ) {
                        [ controller secureCopy ];
                        copying = 1;
                    } else {
                        [ self parseProgressOutputString: ( char * )buf 
                                forController: controller ];
                    } 
                }
                
                if ( strstr(( char * )buf, "Operation timed out" ) != NULL
                        || strstr(( char * )buf, "REMOTE HOST IDENTIFICATION HAS CHANGED" ) != NULL ) {
                    char		*p = strdup(( char * )buf ), *q;
                    
                    if (( q = strrchr( p, '\r' )) != NULL ) *q = '\0';
                            [ controller sessionError:
                                [ NSString stringWithUTF8String: p ]];
                    free( p );
                }

                [ controller addToLog: [ NSString stringWithUTF8String: ( char * )buf ]];
                memset(( char * )buf, '\0', strlen(( char * )buf ));
                [ pool release ];
                if ( noscp ) break;
            }
        }

        scppid = wait( &status );
        
	if ( fclose( mfp ) != 0 ) {
	    [ controller addToLog: [ NSString stringWithFormat:
		    @"fclose failed: %s", strerror( errno ) ]];
	}
	( void )close( masterfd );
	
        [ controller addToLog: [ NSString stringWithUTF8String: ( char * )buf ]];
        [ controller addToLog: [ NSString stringWithFormat:
                    @"\nscp task with pid %d ended with status %d.\n", scppid, WEXITSTATUS( status ) ]];
        [ controller addToLog: @"\n\n" ];
        [ controller secureCopyFinishedWithStatus: ( WEXITSTATUS( status )) ];
        if ( WIFEXITED( status )) {
            [ controller addToLog: @"Normal exit\n" ];
        } else if ( WIFSIGNALED( status )) {
            [ controller addToLog: @"WIFSIGNALED: " ];
            [ controller addToLog: [ NSString stringWithFormat: @"signal = %d\n", status ]];
        } else if ( WIFSTOPPED( status )) {
            [ controller addToLog: @"WIFSTOPPED\n" ];
        }
        
        scppid = 0;
    } else if ( scppid < 0 ) {
        NSLog( @"forkpty failed: %s", strerror( errno ));
    } else {
        execve( executable, ( char ** )execargs, environ );
        NSLog( @"execve failed: %s", strerror( errno ));
        
        _exit( 2 );						/* shouldn't get here */
    }
}

@end
