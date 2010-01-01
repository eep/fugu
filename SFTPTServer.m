/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SFTPTServer.h"
#import "SFTPController.h"
#import	"SFTPNode.h"
#import "NSArray(CreateArgv).h"
#import "NSString-UnknownEncoding.h"
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
#include "fdwrite.h"
#include "typeforchar.h"

extern int	errno;
extern char	**environ;

/* used to set which field contains the filename */
static int      fncolumn = -1;

@implementation SFTPTServer

int		cancelflag = 0;
pid_t		sftppid = 0;
int		connecting = 0;
int		connected = 0;
int		master = 0;

+ ( void )connectWithPorts: ( NSArray * )ports
{
    NSAutoreleasePool		*pool = [[ NSAutoreleasePool alloc ] init ];
    NSConnection		*cnctnToController;
    SFTPTServer			*serverObject;
    
    cnctnToController = [ NSConnection connectionWithReceivePort:
                            [ ports objectAtIndex: 0 ]
                            sendPort: [ ports objectAtIndex: 1 ]];
                            
    serverObject = [[ self alloc ] init ];
    [ (( SFTPController * )[ cnctnToController rootProxy ] ) setServer: serverObject ];
    [ serverObject release ];
    
    [[ NSRunLoop currentRunLoop ] run ];  
    [ pool release ];
}

- ( id )init
{
    _currentTransferName = nil;
    _sftpRemoteObjectList = nil;
    
    return(( self = [ super init ] ) ? self : nil );
}

/* accessor methods */
- ( void )setCurrentTransferName: ( NSString * )name
{
    if ( _currentTransferName != nil ) {
	[ _currentTransferName release ];
	_currentTransferName = nil;
    }
    
    if ( name != nil ) {
	_currentTransferName = [[ NSString alloc ] initWithString: name ];
    } else {
	_currentTransferName = name;
    }
}

- ( NSString * )currentTransferName
{
    return( _currentTransferName );
}

- ( id )remoteObjectList
{
    return( _sftpRemoteObjectList );
}

- ( void )setRemoteObjectList: ( id )objectList
{
    if ( _sftpRemoteObjectList ) {
        [ _sftpRemoteObjectList release ];
        _sftpRemoteObjectList = nil;
    }
    if ( ! objectList ) {
        return;
    }
    
    _sftpRemoteObjectList = [ objectList retain ];
}
/* end accessor methods */

/* sftp/ftp output handler methods */
- ( BOOL )checkForPasswordPromptInBuffer: ( char * )buf
{
#ifdef notdef
    NSArray             *prompts = nil;
#endif /* notdef */
    BOOL                hasPrompt = NO;
    int                 i, pnum = 0;
    char                *prompts[] = { "password", "passphrase",
                                    "Password:", "PASSCODE:",
                                    "Password for ", "Passcode for ",
				    "CryptoCard Challenge" };
                                    
    if ( buf == NULL ) {
        return( NO );
    }
    
    pnum = ( sizeof( prompts ) / sizeof( prompts[ 0 ] ));
    for ( i = 0; i < pnum; i++ ) {
        if ( strstr( buf, prompts[ i ] ) != NULL ) {
            hasPrompt = YES;
            break;
        }
    }
    
#ifdef notdef
    /* someday we'll allow custom prompt checks */
#endif /* notdef */
    
    return( hasPrompt );
}

- ( BOOL )bufferContainsError: ( char * )buf
{
    BOOL                hasError = NO;
    int                 i, numerrs = 0;
    char                *errors[] = { "Permission denied",
                                    "Couldn't ", "Secure connection ",
                                    "No address associated with",
                                    "Connection refused",
                                    "Request for subsystem",
                                    "Cannot download",
                                    "ssh_exchange_identification",
                                    "Operation timed out"
                                    "no address associated with",
                                    "REMOTE HOST IDENTIFICATION HAS CHANGED" };
                                    
    if ( buf == NULL ) {
        return( NO );
    }
                                    
    numerrs = ( sizeof( errors ) / sizeof( errors[ 0 ] ));
    for ( i = 0; i < numerrs; i++ ) {
        if ( strstr( buf, errors[ i ] ) != NULL ) {
            hasError = YES;
            break;
        }
    }
    
    return( hasError );
}

- ( BOOL )hasDirectoryListingFormInBuffer: ( char * )buf
{
    BOOL                hasDirListForm = NO;
    int                 i, numforms = 0;
    char                *lsforms[] = { "ls -l", "ls", "ls " };
    
    if ( buf == NULL ) {
        return( NO );
    }
    
    numforms = ( sizeof( lsforms ) / sizeof( lsforms[ 0 ] ));
    for ( i = 0; i < numforms; i++ ) {
        if ( strncmp( buf, lsforms[ i ], strlen( lsforms[ i ] )) == 0 ) {
            hasDirListForm = YES;
            break;
        }
    }
    
    return( hasDirListForm );
}

- ( BOOL )unknownHostKeyPromptInBuffer: ( char * )buf
{
    BOOL                isPrompt = NO;
    int                 i, numprompts = 0;
    char                *prompts[] = { "The authenticity of ",
                                        "Host key not found ",
					"differs from the key" };
                                        
    numprompts = ( sizeof( prompts ) / sizeof( prompts[ 0 ] ));
    for ( i = 0; i < numprompts; i++ ) {
        if ( strncmp( buf, prompts[ i ], strlen( prompts[ i ] )) == 0 ) {
            isPrompt = YES;
            break;
        }
    }
    
    return( isPrompt );
}

- ( void )parseTransferProgressString: ( char * )string isUploading: ( BOOL )uploading
	forController: ( id )controller
{
    int			tac, i, pc_index = -1;
    char		*tmp, **tav, *p;
    char		*t_rate, *t_amount, *t_eta;
    
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
	    p = '\0';
	    break;
	}
    }
    
    t_amount = tav[ pc_index + 1 ];
    t_rate = tav[ pc_index + 2 ];
    
    if ( pc_index == ( tac - 5 )) {
	t_eta = tav[ pc_index + 3 ];
    } else {
	t_eta = "--:--";
    }
    
    if ( uploading ) {
	[ controller updateUploadProgressBarWithValue: strtod( tav[ pc_index ], NULL )
		    amountTransfered: [ NSString stringWithUTF8String: t_amount ]
		    transferRate: [ NSString stringWithUTF8String: t_rate ]
		    ETA: [ NSString stringWithFormat: @"%s ETA", t_eta ]];
    } else {
	[ controller updateDownloadProgressBarWithValue: strtod( tav[ pc_index ], NULL )
		    amountTransfered: [ NSString stringWithUTF8String: t_amount ]
		    transferRate: [ NSString stringWithUTF8String: t_rate ]
		    ETA: [ NSString stringWithFormat: @"%s ETA", t_eta ]];
    }
    
    free( tmp );
}
/* end sftp/ftp output handler methods */

- ( pid_t )getSftpPid
{
    return( sftppid );
}

- ( int )atSftpPrompt
{
    return( atprompt );
}

- ( NSString * )retrieveUnknownHostKeyFromStream: ( FILE * )stream
{
    NSString            *key = @"";
    char                buf[ MAXPATHLEN * 2 ];
    
    if ( fgets( buf, MAXPATHLEN * 2, stream ) == NULL ) {
        NSLog( @"fgets: %s\n", strerror( errno ));
    } else if (( key = [ NSString stringWithUTF8String: buf ] ) == nil ) {
        key = @"";
    }
    
    return( key );
}

- ( NSMutableDictionary * )remoteObjectFromSFTPLine: ( char * )object
{
    int			j, tac, len;
    int			datecolumn = -1, ownercolumn = 2;
    char                line[ MAXPATHLEN * 2 ] = { 0 };
    char                *filename = NULL;
    char		**targv;
    char                *p;
    NSMutableDictionary	*infoDictionary = nil;
    NSString		*dateString = nil, *groupName = nil, *name = nil;
    NSData              *nameAsRawBytes = nil;

    if ( strncmp( object, "sftp> ", strlen( "sftp> " )) == 0 ) {
        return( nil );
    }
    
    if ( strlen( object ) >= sizeof( line )) {
        NSLog( @"%s: too long\n", object );
        return( nil );
    }
    strcpy( line, object );
    
    /* break up the string into components */
    if (( tac = argcargv( line, &targv )) <= 0 ) {
        return( nil );
    }
    
    /* 
     * much of the abstraction in here to handle an arbitrary number of fields
     * was suggested by Hugues Martel. He used Obj-C calls. C calls are used here,
     * since otherwise there's a lot of unnecessary conversion.
     * Many thanks to Hugues for this contribution.
     */
        
    /* SSH.com's sftp gives true ls -lF output. 		*/
    /* Do we need to add other chars here (>, /, @, =)? 	*/
    if ( tac > 0 ) {
	p = targv[ ( tac - 1 ) ];
	len = strlen( p );
	if ( len > 1 && *targv[ 0 ] == '-' && p[ len - 1 ] == '*' ) {
            p[ len - 1 ] = '\0';
        }
    }
    
    /* SSH.com's sftp client writes dir name + : before listing */
    if ( tac == 1 && strcmp( targv[ 0 ], ".:" ) == 0 ) {
        fncolumn = 8;
        goto DOT_OR_DOTDOT;
    } else if ( tac == 1 ) {
	/* prevent crashes */
	goto DOT_OR_DOTDOT;
    }
    
    /*
     * find the filename column. The first line should contain
     * a filename '.' or './'.
     */
    for ( j = 0; j < tac; j++ ) {
        if ( strcmp( targv[ j ], "." ) == 0 || strcmp( targv[ j ], "./" ) == 0 ) {
            fncolumn = j;
            break;
        }
    }
    /* likewise, determine how many fields are used for the date.	*/
    /* based on code submitted by Hugues Martel.			*/
    if ( fncolumn == -1 ) {
        /* probably an invalid line, but might also be a VShell-like    */
        /* server at the root directory.				*/
        if ( isdigit( *targv[ 0 ] ) && strchr( targv[ 4 ], ':' ) != NULL ) {
            fncolumn = 5;
        } else if ( *targv[ 0 ] == 'd' || *targv[ 0 ] == '-'
                    && tac >= 9 ) {
            /* might also be OpenSSH on Cygwin, which doesn't display	*/
            /* a '.' or './' at the root directory. if so, handle it.	*/
            fncolumn = 8;
        }
    }
    if ( fncolumn == -1 || fncolumn > tac ) {
        return( nil );			/* invalid output */
    }

    for ( j = ( fncolumn - 1 ); j >= 0; j-- ) {
        if ( isalpha( *targv[ j ] )) { 	/* we've found the column containing the month */
            datecolumn = j;
            if ( datecolumn != 5 ) {
                int             ind = 0;
                
                NSLog( @"datecolumn: %d\tdate: %s", datecolumn, targv[ j ] );
                for ( ind = 0; ind < tac; ind++ ) {
                    NSLog( @"targv[ %d ]: %s", ind, targv[ ind ] );
                }
                NSLog( @"line: %s", object );
            }
            break;
        }
    }
    if ( datecolumn < 0 ) {	/* potentially dealing with old OpenSSH version */
        if ( *targv[ 0 ] == '0' && strlen( targv[ 0 ] ) > 1
                                && strchr( targv[ 4 ], ':' ) == NULL
                                && fncolumn == 5 ) {
            datecolumn = ( fncolumn - 1 );
            ownercolumn = 1;
        }
    }
    if ( datecolumn >= tac || datecolumn < 0 ) {
        return( nil );
    }
            
    dateString = [ NSString stringWithUTF8String: targv[ datecolumn ]];
    for ( j = ( datecolumn + 1 ); j < fncolumn; j++ ) {
        dateString = [ NSString stringWithFormat: @"%@ %s", dateString, targv[ j ]];
    }
    infoDictionary = [[ NSMutableDictionary alloc ] init ];
    [ infoDictionary setObject: dateString forKey: @"date" ];
    
    if ( datecolumn >= 1 ) {    /* size always comes before date */
        [ infoDictionary setObject: [ NSString stringWithUTF8String:
                                        targv[ ( datecolumn - 1 ) ]]
                            forKey: @"size" ];
    }
        
    if ( fncolumn > 0 && tac >= ( fncolumn + 1 )) {
        if ( tac > ( fncolumn + 1 )) {
            if ( strstr( targv[ 0 ], "sftp>" ) != NULL ) {
                goto DOT_OR_DOTDOT;
            }
            
            for ( j = fncolumn; j < tac; j++ ) {
                len += ( strlen( targv[ j ] ) + 1 );    /* +1 for spaces */
            }

            if (( filename = ( char * )malloc( len )) == NULL ) {
                NSLog( @"malloc: %s", strerror( errno ));
                exit( 2 );
            }
            strlcpy( filename, targv[ fncolumn ], len );
            
            for ( j = fncolumn + 1; j < tac; j++ ) {
                if ( strcmp( targv[ j ], "->" ) == 0 ) {
                    break;
                }
                strlcat( filename, " ", len );
                strlcat( filename, targv[ j ], len );
            }
            
            nameAsRawBytes = [ NSData dataWithBytes: filename length: strlen( filename ) ];
            name = [ NSString stringWithBytesOfUnknownEncoding: filename
                                                    length: strlen( filename ) ];
            free( filename );
        } else {
            if ( strcmp( ".", targv[ fncolumn ] ) == 0
                    || strcmp( "./", targv[ fncolumn ] ) == 0 /* VShell output */
                    /* || strcmp( "../", targv[ fncolumn ] ) == 0
                    || strcmp( "..", targv[ fncolumn ] ) == 0 */ ) goto DOT_OR_DOTDOT;
            
            nameAsRawBytes = [ NSData dataWithBytes: targv[ fncolumn ]
                                length: strlen( targv[ fncolumn ] ) ];
            name = [ NSString stringWithBytesOfUnknownEncoding: targv[ fncolumn ]
                                            length: strlen( targv[ fncolumn ] ) ];
        }

        if (( datecolumn - 1 ) == 0 ) {		/* dealing with a VShell server, probably. */
            [ infoDictionary setObject: @"N/A" forKey: @"owner" ];
            [ infoDictionary setObject: @"N/A" forKey: @"group" ];
            /* since VShell doesn't include a mode, we have to invent one */
            /* based on code submitted by Hugues Martel. */
            if ( [ name characterAtIndex: ( [ name length ] - 1 ) ] == '/' ) { /* directory */
                [ infoDictionary setObject: @"d---------" forKey: @"perm" ];
                [ infoDictionary setObject: @"directory" forKey: @"type" ];
            } else {
                [ infoDictionary setObject: @"----------" forKey: @"perm" ];
                [ infoDictionary setObject: @"file" forKey: @"type" ];
            }
        } else if (( datecolumn - 1 ) > 1 ) {	/* probably some unix variant */
            [ infoDictionary setObject: [ NSString stringWithUTF8String: targv[ ownercolumn ]]
                                    forKey: @"owner" ];
            groupName = [ NSString stringWithUTF8String: targv[ ( ownercolumn + 1 ) ]];
            /* possible to have group names containing spaces */
            for ( j = ( ownercolumn + 2 ); j < ( datecolumn - 1 ); j++ ) {
                groupName = [ NSString stringWithFormat: @"%@ %s", groupName, targv[ j ]];
            }
            [ infoDictionary setObject: groupName forKey: @"group" ];

            /* handle old OpenSSH server by translating output */
            if (( datecolumn + 1 ) == fncolumn && *targv[ 0 ] == '0' ) {
                [ infoDictionary setObject:
                                    [[ NSString stringWithUTF8String: targv[ 0 ]]
                                        stringRepresentationOfOctalMode ]
                                    forKey: @"perm" ];
            } else {
                [ infoDictionary setObject: [ NSString stringWithUTF8String: targv[ 0 ]]
                                    forKey: @"perm" ];
            }
            [ infoDictionary setObject:
                [ NSString stringWithUTF8String:
                typeforchar( [[ infoDictionary objectForKey: @"perm" ] characterAtIndex: 0 ] ) ]
                            forKey: @"type" ];
        }
        [ infoDictionary setObject: name forKey: @"name" ];
        [ infoDictionary setObject: nameAsRawBytes forKey: @"NameAsRawBytes" ];
    }
    
    return( [ infoDictionary autorelease ] );
    
DOT_OR_DOTDOT:
    if ( infoDictionary ) {
        [ infoDictionary release ];
    }
    return( nil );
}

- ( oneway void )connectToServerWithParams: ( NSArray * )params
                fromController: ( SFTPController * )controller
{
    fd_set		readmask;
    struct winsize	win_size = { 24, 512, 0, 0 };
    FILE		*mf = NULL;
    int			rc, status, pwsent = 0, validpw = 0, showrb = 0, threestrikes = 0;
    int			was_uploading = 0, was_downloading = 0, was_changing = 0, sethomedir = 0;
    int			was_removing = 0, was_renaming = 0, was_listing = 0;
    char		ttyname[ MAXPATHLEN ], **execargs;
    char		buf[ MAXPATHLEN * 2 ];
    NSArray		*argv = nil, *passedInArgs = [ params copy ];    
    NSString    	*sftpBinary;
    
    atprompt = 0;
    remoteDirBuf = [[ NSString alloc ] init ];

    [ controller clearLog ]; 

    if (( sftpBinary = [ NSString pathForExecutable: @"sftp" ] ) == nil ) {
	NSLog( @"Couldn't find sftp!" );
	return;
    }

    argv = [ NSArray arrayWithObject: sftpBinary ];
    
    argv = [ argv arrayByAddingObjectsFromArray: passedInArgs ];
    rc = [ argv createArgv: &execargs ];

    [ passedInArgs release ];

    connecting = 1;
    [ controller addToLog: [ NSString stringWithFormat: @"sftp launch path is %s.\n", execargs[ 0 ]]];
    
    [ controller updateHostList ];	/* adds new host to pop-up list */
    [ controller setConnectedWindowTitle ];
    
    switch (( sftppid = forkpty( &master, ttyname, NULL, &win_size ))) {
    case 0:
        execve( execargs[ 0 ], ( char ** )execargs, environ );
        NSLog( @"Couldn't launch sftp: %s", strerror( errno ));
        _exit( 2 );						/* shouldn't get here */
        
    case -1:
        NSLog( @"forkpty failed: %s", strerror( errno ));
        exit( 2 );
        
    default:
        break;
    }
    
    if ( fcntl( master, F_SETFL, O_NONBLOCK ) < 0 ) {	/* prevent master from blocking */
        NSLog( @"fcntl non-block failed: %s", strerror( errno ));
    }
    
    if (( mf = fdopen( master, "r+" )) == NULL ) {
        NSLog( @"failed to open file stream with fdopen: %s\n", strerror( errno ));
        return;
    }
    setvbuf( mf, NULL, _IONBF, 0 );
    
    [ controller addToLog: [ NSString stringWithFormat: @"Slave terminal device is %s.\n",
                            ttyname ]];
    [ controller addToLog: [ NSString stringWithFormat: @"Master fd is %d.\n",
                            master ]];
    
    for ( ;; ) {
        NSAutoreleasePool		*p = [[ NSAutoreleasePool alloc ] init ];
        remoteDirBuf = @"";
            
        FD_ZERO( &readmask );
        FD_SET( master, &readmask );
        
        switch( select( master + 1, &readmask, NULL, NULL, NULL )) {
        case -1:
            NSLog( @"select: %s", strerror( errno ));
            break;
            
        case 0:	/* timeout */
            continue;
        
        default:
            break;
        }
        
        if ( FD_ISSET( master, &readmask )) {
            if ( fgets(( char * )buf, MAXPATHLEN, mf ) == NULL ) {
                break;
            }
#ifdef DEBUG
            NSLog( @"buf: %s", ( char * )buf );
#endif /* DEBUG */
            
            if ( [ self checkForPasswordPromptInBuffer: buf ] && !validpw ) {
                if ( threestrikes > 0 ) {
                    [ controller passError ];
                };
                if ( connecting ) [ controller requestPasswordWithPrompt: ( char * )buf ];
                pwsent = 1;
            } else if ( strstr(( char * )buf, "rename \"" ) != NULL ) {
                was_renaming = 1;
            } else if ( strstr(( char * )buf, "sftp> " ) != NULL ) {
                atprompt = 1;
                if ( !connected ) {
                    pwsent++;	/* for key auth */
                    validpw++;
                    [ controller showRemoteFiles ];
                    showrb++;
                } else if ( !sethomedir ) {
                    [ controller getListing ];
                    sethomedir++;
                } else if ( was_changing || was_renaming ) {
                    [ controller getListing ];
                    was_changing = 0;
                    was_renaming = 0;
                } else {
                    /* check to see if there's anything waiting to be uploaded */
                    if ( [[ controller uploadQ ] count ] ) {
                        NSDictionary	*dict = [[ controller uploadQ ] objectAtIndex: 0 ];
                        
                        was_uploading = 1;
                        if ( [[ dict objectForKey: @"isdir" ] intValue ] ) {
                            if ( fdwrite( master, "mkdir \"%s\"\n", ( void * )[[ dict objectForKey:
                                                        @"pathfrombase" ] UTF8String ] ) < 0 ) {
                                NSLog( @"Failed to send command: %s", strerror( errno ));
                            }
                        } else {
                            char		*p = " ";
                        
                            if ( [[ NSUserDefaults standardUserDefaults ]
                                            boolForKey: @"RetainFileTimestamp" ] ) {
                                p = " -P ";
                            }
                            
                            if ( fdwrite( master, "put%s\"%s\" \"%s\"\n", p,
                                        ( void * )[[ dict objectForKey: @"fullpath" ] UTF8String ],
                                        ( void * )[[ dict objectForKey:
                                            @"pathfrombase" ] UTF8String ] ) < 0 ) {
                                NSLog( @"Failed to send command: %s", strerror( errno ));
                            }
                        }
                        
                        [ self setCurrentTransferName: [[[[ controller uploadQ ] objectAtIndex: 0 ]
                                    objectForKey: @"fullpath" ] lastPathComponent ]];
                        [ controller showUploadProgress ];
                        [ controller updateUploadProgress: 0 ];
                    } else if ( was_uploading ) {
                        was_uploading = 0;
                        [ self setCurrentTransferName: nil ];
                        [ controller updateUploadProgress: 0 ];
                    }
                    
                    /* check download queue */
                    if ( [[ controller downloadQ ] count ] ) {
                        NSDictionary	*dict = [[ controller downloadQ ] objectAtIndex: 0 ];
                        NSString        *transferName = nil;
                        char		*p = " ";
			char		remote[ MAXPATHLEN ] = { 0 };
			int		len;
                        
                        if ( [[ NSUserDefaults standardUserDefaults ]
                                        boolForKey: @"RetainFileTimestamp" ] ) {
                            p = " -P ";
                        }
			
			if (( len = [(NSData*)[ dict objectForKey: @"rpath" ] length ] ) >= MAXPATHLEN ) {
			    /* XXX throw visible error */
			    NSLog( @"remote path too long" );
			    continue;
			}
			memcpy( remote, [[ dict objectForKey: @"rpath" ] bytes ], len );
                        
                        was_downloading = 1;
                        if ( fdwrite( master, "get%s\"%s\" \"%s\"\n", p, remote,
                                ( void * )[[ dict objectForKey: @"lpath" ] UTF8String ] ) < 0 ) {
                            NSLog( @"Failed to send command: %s", strerror( errno ));
                        }

                        transferName = [ NSString stringWithBytesOfUnknownEncoding:
                                                ( char * )[[ dict objectForKey: @"rpath" ] bytes ]
                                                length: [( NSData * )[ dict objectForKey: @"rpath" ] length ]];
                        [ self setCurrentTransferName: [ transferName lastPathComponent ]];
                        [ controller showDownloadProgressWithMessage:
                                ( char * )[[ transferName lastPathComponent ] UTF8String ]];
                        [ controller removeFirstItemFromDownloadQ ];
                    } else if ( was_downloading ) {
                        was_downloading = 0;
                        [ controller finishedDownload ];
                        [ self setCurrentTransferName: nil ];
                    }
                    
                    /* check remove queue */
                    if ( [[ controller removeQ ] count ] ) {
                        was_removing = 1;
                        [ controller deleteFirstItemFromRemoveQueue ];
                    } else if ( was_removing ) {
                        was_removing = 0;
                        [ controller getListing ];
                    } else if ( was_listing ) {
                        was_listing = 0;
                        [ controller finishedCommand ];
                    }
                }
            } else {
                atprompt = 0;
                
                if ( strncmp(( char * )buf, "Permission denied, ",
                                strlen( "Permission denied, " )) == 0 ) {
                    pwsent = 0;
                    threestrikes++;
                } else if ( [ self bufferContainsError: buf ] ) {
                    [ controller connectionError: [ NSString stringWithUTF8String: buf ]];
                } else if ( [ self currentTransferName ] != nil ) {
                    if ( strstr(( char * )buf, [[ self currentTransferName ] UTF8String ] ) != NULL
                                && strrchr(( char * )buf, '%' ) != NULL ) {
                        if ( was_downloading ) {
                            [ self parseTransferProgressString: ( char * )buf
                                    isUploading: NO
                                    forController: controller ];
                        } else if ( was_uploading ) {
                            [ self parseTransferProgressString: ( char * )buf
                                    isUploading: YES
                                    forController: controller ];
                        }
                    }
                } else if ( strstr(( char * )buf, "passphrase for key" ) != NULL ) {
                    pwsent = 0;
                    threestrikes = 0;	/* if pubkey auth fails, password prompt will appear */
                    [ controller requestPasswordWithPrompt: ( char * )buf ];
                } else if ( strstr(( char * )buf, "Changing owner on" ) != NULL
                        || strstr(( char * )buf, "Changing group on" )
                        || strstr(( char * )buf, "Changing mode on" )) {
                    [ controller setBusyStatusWithMessage: [ NSString stringWithUTF8String:
                                                                                ( void * )buf ]];
                    was_changing = 1;
                    if ( strstr(( char * )buf, "Couldn't " ) != NULL ) {
                        [ controller sessionError: [ NSString stringWithUTF8String: ( void * )buf ]];
                    }
                } else if ( [ self unknownHostKeyPromptInBuffer: buf ] ) {
                    NSMutableDictionary    *hostInfo = nil;
                    
                    hostInfo = [ NSMutableDictionary dictionaryWithObjectsAndKeys:
                                [ NSString stringWithUTF8String: buf ], @"msg",
                                [ self retrieveUnknownHostKeyFromStream: mf ], @"key", nil ];
                    
                    [ controller getContinueQueryForUnknownHost: ( NSDictionary * )hostInfo ];
                } else if ( strstr(( char * )buf, "Removing " ) != NULL ) {
                    [ controller setBusyStatusWithMessage:
                        [ NSString stringWithUTF8String: ( char * )buf ]];
                }
            }

            /* moved to separate if block: sometimes ls and sftp> occur in same buffer */
            if ( [ self hasDirectoryListingFormInBuffer: buf ] && connected ) {
                [ controller addToLog: [ NSString stringWithUTF8String: ( char * )buf ]];
                was_listing = 1;
                [ self collectListingFromMaster: master fileStream: mf forController: controller ];
                memset( buf, '\0', strlen(( char * )buf ));
                [ controller loadRemoteBrowserWithItems: [ self remoteObjectList ]];
                remoteDirBuf = @"";
            }
            
            if ( strstr(( char * )buf, "Remote working" ) != NULL ) {
                char		*p, *q, *tmp;
            
                tmp = strdup(( char * )buf );

                if (( q = strrchr( tmp, '\r' )) != NULL ) *q = '\0';
                
                p = strchr( tmp, '/' );
                
                [ controller setRemotePathPopUp:
                    [ NSString stringWithBytesOfUnknownEncoding: p 
                                            length: strlen( p ) ]];
                free( tmp );
            }
            
            if ( threestrikes >= 3 ) {
                [ controller cancelConnection: nil ];
            }
            
            if ( buf[ 0 ] != '\0' ) {
                [ controller addToLog: [ NSString stringWithUTF8String: ( void * )buf ]];
                memset( buf, '\0', strlen(( char * )buf ));
            }
        }

        [ p release ];
        p = nil;
        if ( cancelflag ) break;
    }
    
    sftppid = wait( &status );
    
    free( execargs );
    [ self setCurrentTransferName: nil ];
    [ remoteDirBuf release ];
    connected = 0;
    ( void )close( master );

    [ controller cleanUp ];
    [ controller addToLog: [ NSString stringWithUTF8String: ( void * )buf ]];
    [ controller addToLog: [ NSString stringWithFormat: @"\nsftp task with pid %d ended.\n", sftppid ]];
    sftppid = 0;

    if ( WIFEXITED( status )) {
        [ controller addToLog: @"Normal exit\n" ];
    } else if ( WIFSIGNALED( status )) {
        [ controller addToLog: @"WIFSIGNALED: " ];
        [ controller addToLog: [ NSString stringWithFormat: @"signal = %d\n", status ]];
    } else if ( WIFSTOPPED( status )) {
        [ controller addToLog: @"WIFSTOPPED\n" ];
    }
}

- ( void )collectListingFromMaster: ( int )master fileStream: ( FILE * )stream
            forController: ( SFTPController * )controller
{
    char                buf[ MAXPATHLEN * 2 ] = { 0 };
    char                tmp1[ MAXPATHLEN * 2 ], tmp2[ MAXPATHLEN * 2 ];
    int                 len, incomplete_line = 0;
    fd_set              readmask;
    NSMutableDictionary *object = nil;
    NSMutableArray      *items = nil;
    
    /* make sure we're not buffering */
    setvbuf( stream, NULL, _IONBF, 0 );
    
    for ( ;; ) {
        FD_ZERO( &readmask );
        FD_SET( master, &readmask );
        if ( select( master + 1, &readmask, NULL, NULL, NULL ) < 0 ) {
            NSLog( @"select() returned a value less than zero" );
            return;
        }
        
        if ( FD_ISSET( master, &readmask )) {
            if ( fgets(( char * )buf, ( MAXPATHLEN * 2 ), stream ) == NULL ) {
                return;
            }

            if ( [ self bufferContainsError: buf ] ) {
                [ controller sessionError: [ NSString stringWithUTF8String: buf ]];
                continue;
            }
#ifdef SSH_COM_SUPPORT
            if ( strstr( buf, "<Press any key" ) != NULL ) {
                /* SSH.com's sftp makes you hit a key to get to the prompt. Whee. */
                fdwrite( master, " " );
                continue;
            }
#endif /* SSH_COM_SUPPORT */
            
            /*
             * This is kind of nasty. We don't always get a full line
             * from the server in the 'ls' output, so we have to check
             * if that's the case, flag it, and append the rest of the 
             * text after the next read from the server. Yar!
             */
            len = strlen( buf );
            /* XXX should be modified to handle arbitrary chunks of line */
            if ( strncmp( "sftp>", buf, strlen( "sftp>" )) != 0 &&
                    buf[ len - 1 ] != '\n' ) {
                if ( strlen( buf ) >= sizeof( tmp1 )) {
                    NSLog( @"%s: too long", buf );
                    continue;
                }
                strcpy( tmp1, buf );
                incomplete_line = 1;
                continue;
            }
            if ( incomplete_line ) {
                /* we know this is safe because they're the same buf size */
                strcpy( tmp2, buf );
                memset( buf, '\0', sizeof( buf ));
                
                if ( snprintf( buf, sizeof( buf ), "%s%s", tmp1, tmp2 ) >= sizeof( buf )) {
                    NSLog( @"%s%s: too long", tmp1, tmp2 );
                    continue;
                }
                incomplete_line = 0;
            }
            
            if (( object = [ self remoteObjectFromSFTPLine: buf ] ) != nil ) {
                if ( items == nil ) {
                    items = [[[ NSMutableArray alloc ] init ] autorelease ];
                }
                [ items addObject: object ];
            }
            
            [ controller addToLog: [ NSString stringWithBytesOfUnknownEncoding: buf
                                                length: strlen( buf ) ]];
            if ( strstr( buf, "sftp>" ) != NULL ) {
                memset( buf, '\0', strlen( buf ));
                [ controller finishedCommand ];
                [ self setRemoteObjectList: items ];
                return;
            }
        
            memset( buf, '\0', strlen(( char * )buf ));
        }
    }   
}

@end
