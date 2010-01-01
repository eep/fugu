/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SFTPMainWindow.h"
#import "SFTPTServer.h"
#import "SFTPController.h"
#import "SFTPNode.h"
#import "SFTPErrorHandler.h"
#import "SFTPItemCell.h"
#import "SCPController.h"
#import "SSHTunnel.h"
#import "UMVersionCheck.h"
#import "UMFileLauncher.h"

#import "NSAttributedString-Ellipsis.h"
#import "NSCalendarDate(ConvertToSeconds).h"
#import "NSFileManager(mktemp).h"
#import "NSImage(IconForType).h"
#import "NSMutableArray(Extensions).h"
#import "NSSet(ImageExtensions).h"
#import "NSString(SSHAdditions).h"
#import "NSString(FSRefAdditions).h"
#import "NSString-UnknownEncoding.h"
#import "NSWorkspace(LaunchServices).h"
#import "NSWorkspace(SystemVersionNumber).h"

#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include <CoreFoundation/CoreFoundation.h>

#include "ODBEditorSuite.h"

#include <sys/types.h>
#include <sys/file.h>
#include <sys/param.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <dirent.h>
#include <fcntl.h>
#include <fts.h>
#include <pwd.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <util.h>

#include "argcargv.h"
#include "typeforchar.h"
#include "fdwrite.h"
#include "keychain.h"
#include "sshversion.h"

#define C_TMPFUGUDIR	"/private/tmp/Fugu"
#define OBJC_TMPFUGUDIR	@"/private/tmp/Fugu"

NSString		*basedir = nil;

extern int		cancelflag;
extern pid_t		sftppid;
extern int		connecting;
extern int		connected;
extern int		master;

static float		dltime, ultime;
static int		scp_service = 0;
static NSTimer		*timer;
static NSMutableString	*typeAheadString = nil;
static char		*lsform;
static float		ssh_version;

    int
namecmp( id ob1, id ob2, void *context )
{
    unsigned		*sorttype;
    
    sorttype = ( unsigned * )context;
    
    return( [[ ob1 objectForKey: @"name" ]
                compare: [ ob2 objectForKey: @"name" ]
                options: *sorttype ] );
}

    int
datecmp( id ob1, id ob2, void *context )
{
    NSComparisonResult	result = NSOrderedSame;
    off_t		d1, d2;
    
    d1 = [ NSCalendarDate secondsFromFormattedDateString:
                            [ ob1 objectForKey: @"date" ]];
    d2 = [ NSCalendarDate secondsFromFormattedDateString:
                            [ ob2 objectForKey: @"date" ]];
    
    if ( d1 < d2 ) {
        result = NSOrderedAscending;
    } else if ( d2 < d1 ) {
        result = NSOrderedDescending;
    } else {
        result = namecmp( ob1, ob2, context );
    }
    
    return( result );
}

    int
sizecmp( id ob1, id ob2, void *context )
{
    NSComparisonResult	result = NSOrderedSame;
    NSString		*size1 = [ ob1 objectForKey: @"size" ];
    NSString		*size2 = [ ob2 objectForKey: @"size" ];
    long long int	s1, s2;
    
    s1 = strtoll(( char * )[ size1 UTF8String ], NULL, 10 );
    s2 = strtoll(( char * )[ size2 UTF8String ], NULL, 10 );
    
    if ( s1 < s2 ) {
        result = NSOrderedAscending;
    } else if ( s2 < s1 ) {
        result = NSOrderedDescending;
    } else {
        result = namecmp( ob1, ob2, context );
    }
    
    return( result );
}

    int
ownercmp( id ob1, id ob2, void *context )
{
    return( [[ ob1 objectForKey: @"owner" ]
                compare: [ ob2 objectForKey: @"owner" ]
                options: NSLiteralSearch ] );
}

    int
groupcmp( id ob1, id ob2, void *context )
{
    return( [[ ob1 objectForKey: @"group" ]
                compare: [ ob2 objectForKey: @"group" ]
                options: NSLiteralSearch ] );
}

    int
permcmp( id ob1, id ob2, void *context )
{
    return( [[ ob1 objectForKey: @"perm" ]
                compare: [ ob2 objectForKey: @"perm" ]
                options: NSLiteralSearch ] );
}

    int
( *sortFunctionForIdentifier( id identifier ))( id, id, void * )
{
    if ( [ identifier isEqualToString: @"namecolumn" ] ) {
        return( &namecmp );
    } else if ( [ identifier isEqualToString: @"datecolumn" ] ) {
        return( &datecmp );
    } else if ( [ identifier isEqualToString: @"sizecolumn" ] ) {
        return( &sizecmp );
    } else if ( [ identifier isEqualToString: @"ownercolumn" ] ) {
        return( &ownercmp );
    } else if ( [ identifier isEqualToString: @"groupcolumn" ] ) {
        return( &groupcmp );
    } else if ( [ identifier isEqualToString: @"permcolumn" ] ) {
        return( &permcmp );
    }
    
    return( 0 );
}

@implementation SFTPController

- ( void )establishDOConnection
{
    NSPort		*recPort;
    NSPort		*sendPort;
    NSArray		*portArray;
    
    /* prepare distributed objects for sftp task thread, but don't establish connection yet */
    recPort = [ NSPort port ];
    sendPort = [ NSPort port ];
    connectionToTServer = [[ NSConnection alloc ] initWithReceivePort: recPort
                                                sendPort: sendPort ];
    [ connectionToTServer setRootObject: self ];
    tServer = nil;
    portArray = [ NSArray arrayWithObjects: sendPort, recPort, nil ];
    
    [ NSThread detachNewThreadSelector: @selector( connectWithPorts: )
                                        toTarget: [ SFTPTServer class ]
                                        withObject: portArray ];
}

- ( id )init
{
    uploadQueue = [[ NSMutableArray alloc ] init ];
    downloadQueue = [[ NSMutableArray alloc ] init ];
 
    [ self establishDOConnection ];
    [ NSApp setDelegate: self ];
    
    /* watch for important notifications */
    [[ NSNotificationCenter defaultCenter ] addObserver: self
                                            selector: @selector( enableFavButton: )
                                            name: NSControlTextDidChangeNotification
                                            object: nil ];
                                            
    [[ NSNotificationCenter defaultCenter ] addObserver: self
                                            selector: @selector( reloadDefaults )
                                            name: SFTPPrefsChangedNotification
                                            object: nil ];
            
                                            
    prefs = nil;
    editedDocuments = nil;
    previewedImage = nil;
    cachedPreviews = nil;
    sshServiceBrowser = nil;
    services = nil;
    scp = nil;
    _springLoadedRootPath = nil;
    _sftpCommandQueue = nil;
    
#ifdef notdef
    [[ NSAppleEventManager sharedAppleEventManager ] setEventHandler: self
	    andSelector: @selector( testHandleEvent:replyEvent: )
	    forEventClass: kODBEditorSuite andEventID: kAEModifiedFile ];
    [[ NSAppleEventManager sharedAppleEventManager ] setEventHandler: self
	    andSelector: @selector( testHandleEvent:replyEvent: )
	    forEventClass: kODBEditorSuite andEventID: kAEClosedFile ];
#endif notdef
                                            
    return (( self = [ super init ] ) ? self : nil );
}

- ( void )setServer: ( id )serverObject
{
    [ serverObject setProtocolForProxy: @protocol( SFTPTServerInterface ) ];
    [ serverObject retain ];
    
    tServer = ( SFTPTServer <SFTPTServerInterface> * )serverObject;
}

- ( BOOL )validateMenuItem: ( NSMenuItem * )anItem
{
    if ( [[ anItem title ] isEqualToString:
                        NSLocalizedString( @"Disconnect", @"Disconnect" ) ] ) {
        [ anItem setAction: @selector( disconnect: ) ];
        if ( ! connected ) return( NO );
        else return( YES );
    } else if ( [[ anItem title ] isEqualToString:
                        NSLocalizedString( @"Show Hidden Files", @"Show Hidden Files" ) ] ) {
        if ( dotflag ) {
            [ dotMenuItem setTitle:
                    NSLocalizedString( @"Hide Special Files", @"Hide Special Files" ) ];
        }
    } else if ( [[ anItem title ] isEqualToString:
                        NSLocalizedString( @"Hide Special Files", @"Hide Special Files" ) ] ) {
        if ( ! dotflag ) {
            [ dotMenuItem setTitle:
                    NSLocalizedString( @"Show Hidden Files", @"Show Hidden Files" ) ];
        }
    } else if ( [[ anItem title ] isEqualToString:
                        NSLocalizedString( @"Upload", @"Upload" ) ] ) {
        if ( ! connected ) return( NO );
    } else if ( [[ anItem title ] isEqualToString:
                    NSLocalizedString( @"Focus on Remote Pane", @"Focus on Remote Pane" ) ] ) {
        if ( ! connected ) return( NO );
    } else if ( [[ anItem title ] isEqualToString:
		NSLocalizedString( @"Edit with Text Editor", @"Edit with Text Editor" ) ] ) {
	id		browser = nil;
	NSArray		*items = nil;
	int		row;
	id		item = nil;
        NSString	*type = nil;
	
	if ( [[[ localBrowser window ] firstResponder ] isEqual: localBrowser ] ) {
	    browser = localBrowser;
	    items = ( dotflag ? localDirContents : dotlessLDir );
	} else if ( [[[ localBrowser window ] firstResponder ] isEqual: remoteBrowser ] ) {
	    browser = remoteBrowser;
	    items = ( dotflag ? remoteDirContents : dotlessRDir );
	} else if ( [[[ localBrowser window ] firstResponder ] isEqual: localTableMenu ] ) {
	    NSLog( @"menu" );
	    return( YES );
	}
	
	if (( row = [ browser selectedRow ] ) < 0 ) {
	    return( NO );
	}
	
	item = [ items objectAtIndex: row ];
        type = [ item objectForKey: @"type" ];
	
	if ( [ browser isEqual: localBrowser ] ) {
	    if ( ! [ type isEqualToString: @"file" ] ) {
                return( NO );
            }
	} else if ( [ browser isEqual: remoteBrowser ] ) {
	    if ( ! [[ item objectForKey: @"type" ] isEqualToString: @"file" ] ) {
		return( NO );
	    }
	}
    }
    
    return( YES );
}

- ( IBAction )focusOnLocalPane: ( id )sender
{
    [[ localBrowser window ] makeFirstResponder: localBrowser ];
}

- ( IBAction )focusOnRemotePane: ( id )sender
{
    [[ remoteBrowser window ] makeFirstResponder: remoteBrowser ];
}

- ( void )toolbarSetup
{
    NSToolbar *sftptbar = [[[ NSToolbar alloc ] initWithIdentifier:  @"RXTranscript tbar" ] autorelease ];
    
    [ sftptbar setAllowsUserCustomization: YES ];
    [ sftptbar setAutosavesConfiguration: YES ];
    [ sftptbar setDisplayMode: NSToolbarDisplayModeIconAndLabel ];
    
    [ sftptbar setDelegate: self ];
    [ mainWindow setToolbar: sftptbar ];
}

/**/
/* required toolbar delegate methods */
/**/

- ( NSToolbarItem * )toolbar: ( NSToolbar * )toolbar itemForItemIdentifier: ( NSString * )itemIdent willBeInsertedIntoToolbar: ( BOOL )flag
{
    NSToolbarItem *sftptbarItem = [[[ NSToolbarItem alloc ]
                                    initWithItemIdentifier: itemIdent ] autorelease ];
    
    if ( [ itemIdent isEqualToString: SFTPToolbarLocalHomeIdentifier ] ) {
        [ sftptbarItem setLabel:
                NSLocalizedStringFromTable( @"Local Home", @"SFTPToolbar",
                                            @"Local Home" ) ];
        [ sftptbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"Local Home", @"SFTPToolbar",
                                            @"Local Home" ) ];
        [ sftptbarItem setToolTip:
                NSLocalizedStringFromTable( @"Go to local home directory.", @"SFTPToolbar",
                                            @"Go to local home directory." ) ];
        [ sftptbarItem setImage: [ NSImage imageNamed: @"home.png" ]];
        [ sftptbarItem setAction: @selector( cdLocalHome: ) ];
        [ sftptbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPToolbarNewDirIdentifier ] ) {
        [ sftptbarItem setLabel:
                NSLocalizedStringFromTable( @"New Folder", @"SFTPToolbar",
                                            @"New Folder" ) ];
        [ sftptbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"New Folder", @"SFTPToolbar",
                                            @"New Folder" ) ];
        [ sftptbarItem setToolTip:
                NSLocalizedStringFromTable( @"Make new folder.", @"SFTPToolbar",
                                            @"Make new folder." ) ];
        [ sftptbarItem setImage: [ NSImage imageNamed: @"newfolder.png" ]];
        [ sftptbarItem setAction: @selector( createNewDirectory: ) ];
        [ sftptbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPToolbarDeleteIdentifier ] ) {
        [ sftptbarItem setLabel:
                NSLocalizedStringFromTable( @"Delete", @"SFTPToolbar",
                                            @"Delete" ) ];
        [ sftptbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"Delete", @"SFTPToolbar",
                                            @"Delete" ) ];
        [ sftptbarItem setToolTip:
                NSLocalizedStringFromTable( @"Move selected items to trash.", @"SFTPToolbar",
                                            @"Move selected items to trash." ) ];
        [ sftptbarItem setImage: nil ];
        [ sftptbarItem setImage: [ NSImage imageNamed: @"trash.png" ]];
        [ sftptbarItem setAction: @selector( delete: ) ];
        [ sftptbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPToolbarConnectIdentifier ] ) {
        [ sftptbarItem setLabel:
            NSLocalizedStringFromTable( @"Disconnect", @"SFTPToolbar",
                                        @"Disconnect" ) ];
        [ sftptbarItem setPaletteLabel:
            NSLocalizedStringFromTable( @"Disconnect", @"SFTPToolbar",
                                        @"Disconnect" ) ];
        [ sftptbarItem setToolTip:
            NSLocalizedStringFromTable( @"Disconnect", @"SFTPToolbar",
                                        @"Disconnect" ) ];
        [ sftptbarItem setAction: @selector( disconnect: ) ];
        [ sftptbarItem setImage: [ NSImage imageNamed: @"disconnect.png" ]];
        [ sftptbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPToolbarInfoIdentifier ] ) {
        [ sftptbarItem setLabel:
                NSLocalizedStringFromTable( @"Info", @"SFTPToolbar",
                                            @"Info" ) ];
        [ sftptbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"Info", @"SFTPToolbar",
                                            @"Info" ) ];
        [ sftptbarItem setToolTip:
                NSLocalizedStringFromTable( @"Get information for the selected item.", 
                            @"SFTPToolbar", @"Get information for the selected item." ) ];
        [ sftptbarItem setImage: [ NSImage imageNamed: @"info.png" ]];
        [ sftptbarItem setAction: @selector( getInfo: ) ];
        [ sftptbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPToolbarRemoteHomeIdentifier ] ) {
        [ sftptbarItem setLabel:
                NSLocalizedStringFromTable( @"Remote Home", @"SFTPToolbar",
                                            @"Remote Home" ) ];
        [ sftptbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"Remote Home", @"SFTPToolbar",
                                            @"Remote Home" ) ];
        [ sftptbarItem setToolTip:
                NSLocalizedStringFromTable( @"Go to remote home directory.", @"SFTPToolbar",
                                            @"Go to remote home directory." ) ];
        [ sftptbarItem setImage: [ NSImage imageNamed: @"remotehome.png" ]];
        [ sftptbarItem setAction: @selector( cdRemoteHome: ) ];
        [ sftptbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPToolbarRefreshIdentifier ] ) {
        [ sftptbarItem setLabel:
                NSLocalizedStringFromTable( @"Reload", @"SFTPToolbar",
                                            @"Reload" ) ];
        [ sftptbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"Reload", @"SFTPToolbar",
                                            @"Reload" ) ];
        [ sftptbarItem setToolTip: 
                NSLocalizedStringFromTable( @"Reload current item display.", @"SFTPToolbar",
                                            @"Reload current item display." )];
        [ sftptbarItem setImage: [ NSImage imageNamed: @"reload.png" ]];
        [ sftptbarItem setAction: @selector( refreshBrowsers: ) ];
        [ sftptbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPToolbarUploadIdentifier ] ) {
        [ sftptbarItem setLabel:
                NSLocalizedStringFromTable( @"Upload", @"SFTPToolbar",
                                            @"Upload" ) ];
        [ sftptbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"Upload", @"SFTPToolbar",
                                            @"Upload" ) ];
        [ sftptbarItem setToolTip:
                NSLocalizedStringFromTable( @"Upload selected items to server.", @"SFTPToolbar",
                                            @"Upload selected items to server." ) ];
        [ sftptbarItem setImage: [ NSImage imageNamed: @"upload.png" ]];
        [ sftptbarItem setAction: @selector( uploadButtonClick: ) ];
        [ sftptbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPToolbarDownloadIdentifier ] ) {
        [ sftptbarItem setLabel:
                NSLocalizedStringFromTable( @"Download", @"SFTPToolbar",
                                            @"Download" ) ];
        [ sftptbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"Download", @"SFTPToolbar",
                                            @"Download" ) ];
        [ sftptbarItem setToolTip:
                NSLocalizedStringFromTable( @"Download selected items from server.", @"SFTPToolbar",
                                            @"Download selected items from server." ) ];
        [ sftptbarItem setImage: [ NSImage imageNamed: @"download.png" ]];
        [ sftptbarItem setAction: @selector( downloadButtonClick: ) ];
        [ sftptbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPToolbarGotoIdentifier ] ) {
        [ sftptbarItem setLabel:
                NSLocalizedStringFromTable( @"Go To...", @"SFTPToolbar",
                                            @"Go To..." ) ];
        [ sftptbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"Go To...", @"SFTPToolbar",
                                            @"Go To..." ) ];
        [ sftptbarItem setToolTip:
                NSLocalizedStringFromTable( @"Go directly to a directory.", @"SFTPToolbar",
                                            @"Go directly to a directory." ) ];
        [ sftptbarItem setImage: [ NSImage imageNamed: @"goto.png" ]];
        [ sftptbarItem setAction: @selector( getGotoDirPanel: ) ];
        [ sftptbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPToolbarLocalHistoryIdentifier ] ) {
        [ sftptbarItem setLabel:
                NSLocalizedStringFromTable( @"History", @"SFTPToolbar",
                                            @"History" ) ];
        [ sftptbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"History", @"SFTPToolbar",
                                            @"History" ) ];
        [ sftptbarItem setToolTip:
                NSLocalizedStringFromTable( @"List of local directories viewed during this session.",
                            @"SFTPToolbar", @"List of local directories viewed during this session." ) ];
        [ sftptbarItem setImage: [ NSImage imageNamed: @"history.png" ]];
        [ sftptbarItem setAction: @selector( showLocalHistoryMenu: ) ];
        [ sftptbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPToolbarRemoteHistoryIdentifier ] ) {
        [ sftptbarItem setLabel:
                NSLocalizedStringFromTable( @"History", @"SFTPToolbar",
                                            @"History" ) ];
        [ sftptbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"History", @"SFTPToolbar",
                                            @"History" ) ];
        [ sftptbarItem setToolTip:
                NSLocalizedStringFromTable( @"List of remote directories visited during this session.",
                        @"SFTPToolbar", @"List of remote directories visited during this session." ) ];
        [ sftptbarItem setImage: [ NSImage imageNamed: @"remotehistory.png" ]];
        [ sftptbarItem setAction: @selector( showRemoteHistoryMenu: ) ];
        [ sftptbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPToolbarRemoteItemPreviewIdentifier ] ) {
        [ sftptbarItem setLabel:
                NSLocalizedStringFromTable( @"Preview", @"SFTPToolbar",
                                            @"Preview" ) ];
        [ sftptbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"Preview", @"SFTPToolbar",
                                            @"Preview" ) ];
        [ sftptbarItem setToolTip:
                NSLocalizedStringFromTable( @"Preview selected remote item.", @"SFTPToolbar",
                                            @"Preview selected remote item." ) ];
        [ sftptbarItem setImage: [ NSImage imageNamed: @"preview.png" ]];
        [ sftptbarItem setAction: @selector( previewItem: ) ];
        [ sftptbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPToolbarEditDocumentIdentifier ] ) {
        [ sftptbarItem setLabel:
                NSLocalizedStringFromTable( @"Edit", @"SFTPToolbar",
                                            @"Edit" ) ];
        [ sftptbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"Edit", @"SFTPToolbar",
                                            @"Edit" ) ];
        [ sftptbarItem setToolTip:
                NSLocalizedStringFromTable( @"Edit selected item in external editor.", @"SFTPToolbar",
                                            @"Edit selected item in external editor." ) ];
        [ sftptbarItem setImage: [ NSImage imageNamed: @"edit.png" ]];
        [ sftptbarItem setAction: @selector( editFile: ) ];
        [ sftptbarItem setTarget: self ];
#ifdef notdef
    } else if ( [ itemIdent isEqualToString: SFTPToolbarToggleBrowserMode ] ) {
	/* XXX check current mode, set label and palette label for one- or two-panes */
        [ sftptbarItem setLabel:
                NSLocalizedStringFromTable( @"", @"SFTPToolbar",
                                            @"" ) ];
        [ sftptbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"", @"SFTPToolbar",
                                            @"" ) ];
        [ sftptbarItem setToolTip:
                NSLocalizedStringFromTable( @"Toggle mode", @"SFTPToolbar",
                                            @"Toggle mode" ) ];
        [ sftptbarItem setImage: [ NSImage imageNamed: @"edit.png" ]];
        [ sftptbarItem setAction: @selector( toggleBrowserMode: ) ];
        [ sftptbarItem setTarget: self ];
#endif notdef
    }
            
    return( sftptbarItem );
}

- ( BOOL )validateToolbarItem: ( NSToolbarItem * )tItem
{
    if ( [[ tItem itemIdentifier ] isEqualToString: SFTPToolbarConnectIdentifier ]
            && ! connected ) {
        return( NO );
    } else if ( [[ tItem itemIdentifier ] isEqualToString: SFTPToolbarDeleteIdentifier ] ) {
        if ( ! connected && ! [[ mainWindow firstResponder ] isEqual: localBrowser ] ) {
            [ tItem setImage: [ NSImage imageNamed: @"trash.png" ]];
            return( NO );
        } else if ( [[ mainWindow firstResponder ] isEqual: localBrowser ] ) {
            [ tItem setToolTip:
                    NSLocalizedStringFromTable(
                        @"Move selected local items or directories to the trash.", @"SFTPToolbar",
                        @"Move selected local items or directories to the trash." ) ];
            [ tItem setImage: nil ];
            [ tItem setImage: [ NSImage imageNamed: @"trash.png" ]];
        } else if ( [[ mainWindow firstResponder ] isEqual: remoteBrowser ] ) {
            [ tItem setToolTip:
                    NSLocalizedStringFromTable( @"Delete selected item from server.", @"SFTPToolbar",
                                                @"Delete selected item from server." ) ];
            [ tItem setImage: nil ];
            [ tItem setImage: [ NSImage imageNamed: @"remotetrash.png" ]];
        }
    } else if ( [[ tItem itemIdentifier ] isEqualToString: SFTPToolbarRemoteHomeIdentifier ]
            && !connected ) {
        return( NO );
    } else if ( [[ tItem itemIdentifier ] isEqualToString: SFTPToolbarUploadIdentifier ]
            && !connected ) {
        return( NO );
    } else if ( [[ tItem itemIdentifier ] isEqualToString: SFTPToolbarDownloadIdentifier ]
            && !connected ) {
        return( NO );
    } else if ( [[ tItem itemIdentifier ] isEqualToString: SFTPToolbarRemoteHistoryIdentifier ]
            && !connected ) {
        return( NO );
    } else if ( [[ tItem itemIdentifier ] isEqualToString: SFTPToolbarRemoteItemPreviewIdentifier ] ) {
        if ( ! [[ mainWindow firstResponder ] isKindOfClass: [ SFTPTableView class ]] ) {
            return( NO );
        }
    } else if ( [[ tItem itemIdentifier ] isEqualToString: SFTPToolbarEditDocumentIdentifier ] ) {
        if ( [[ mainWindow firstResponder ] isEqual: localBrowser ] ) {
            id			items = ( dotflag ? localDirContents : dotlessLDir );
            
            if ( [ localBrowser selectedRow ] < 0 ||
                    [[[ items objectAtIndex: [ localBrowser selectedRow ]]
                            objectForKey: @"type" ] isEqualToString: @"directory" ] ) {
                return( NO );
            }
            
        } else if ( [[ mainWindow firstResponder ] isEqual: remoteBrowser ] ) {
            id			items = ( dotflag ? remoteDirContents : dotlessRDir );
            
            if ( [ remoteBrowser selectedRow ] < 0 ||
                    [[[ items objectAtIndex: [ remoteBrowser selectedRow ]]
                            objectForKey: @"type" ] isEqualToString: @"directory" ]) {
                return( NO );
            }
        } else {
            return( NO );
        }
    }
    
    return( YES );
}

- ( NSArray * )toolbarDefaultItemIdentifiers: ( NSToolbar * )toolbar
{
    NSArray	*tmp = [ NSArray arrayWithObjects:
                            SFTPToolbarLocalHomeIdentifier,
                            SFTPToolbarLocalHistoryIdentifier,
                            NSToolbarSeparatorItemIdentifier,
                            NSToolbarFlexibleSpaceItemIdentifier,
                            SFTPToolbarGotoIdentifier,
                            SFTPToolbarRefreshIdentifier,
                            SFTPToolbarInfoIdentifier,
                            SFTPToolbarEditDocumentIdentifier,
                            SFTPToolbarNewDirIdentifier,
                            SFTPToolbarDeleteIdentifier,
                            SFTPToolbarConnectIdentifier,
                            NSToolbarFlexibleSpaceItemIdentifier,
                            NSToolbarSeparatorItemIdentifier,
                            SFTPToolbarRemoteHomeIdentifier,
                            SFTPToolbarRemoteHistoryIdentifier, nil ];
                            
    return( tmp );
}

- ( NSArray * )toolbarAllowedItemIdentifiers: ( NSToolbar * )toolbar
{
    NSArray	*tmp = [ NSArray arrayWithObjects:
                            SFTPToolbarLocalHomeIdentifier,
                            SFTPToolbarDeleteIdentifier,
                            NSToolbarSeparatorItemIdentifier,
                            NSToolbarFlexibleSpaceItemIdentifier,
                            SFTPToolbarRefreshIdentifier,
                            SFTPToolbarNewDirIdentifier,
                            SFTPToolbarConnectIdentifier,
                            SFTPToolbarInfoIdentifier,
                            SFTPToolbarDownloadIdentifier,
                            SFTPToolbarUploadIdentifier,
                            SFTPToolbarGotoIdentifier,
                            SFTPToolbarRemoteHomeIdentifier,
                            SFTPToolbarLocalHistoryIdentifier,
                            SFTPToolbarRemoteHistoryIdentifier,
                            SFTPToolbarRemoteItemPreviewIdentifier,
                            SFTPToolbarEditDocumentIdentifier, nil ];
                            
    return( tmp );
}
/* end required toolbar delegate methods */

- ( void )setMenuOnStateForColumnWithIdentifier: ( id )identifier
{
    if ( [ identifier isEqualToString: @"datecolumn" ] ) {
        [ viewModDateMenuItem setState: NSOnState ];
    } else if ( [ identifier isEqualToString: @"groupcolumn" ] ) {
        [ viewGroupMenuItem setState: NSOnState ];
    } else if ( [ identifier isEqualToString: @"ownercolumn" ] ) {
        [ viewOwnerMenuItem setState: NSOnState ];
    } else if ( [ identifier isEqualToString: @"permcolumn" ] ) {
        [ viewModeMenuItem setState: NSOnState ];
    } else if ( [ identifier isEqualToString: @"sizecolumn" ] ) {
        [ viewSizeMenuItem setState: NSOnState ];
    }
}

- ( IBAction )showItemFromHelpMenu: ( id )sender
{
    UMFileLauncher	*launcher;
    NSString		*path = nil;
    
    if ( [ sender isKindOfClass: [ NSMenuItem class ]] ) {
        if ( [[ sender title ] isEqualToString:
                    NSLocalizedStringFromTable( @"Fugu README", @"HelpMenu",
                            @"Fugu README" ) ] ) {
            path = [ NSBundle pathForResource: @"Fugu README" ofType: @"rtfd"
                        inDirectory: [[ NSBundle mainBundle ] bundlePath ]];
        } else if ( [[ sender title ] isEqualToString:
                    NSLocalizedStringFromTable( @"Keyboard Shortcuts", @"HelpMenu",
                            @"Keyboard Shortcuts" ) ] ) {
             path = [[ NSBundle mainBundle ] pathForResource: @"keys"
                                                        ofType: @"rtf" ];
        } else if ( [[ sender title ] isEqualToString:
                    NSLocalizedStringFromTable( @"Fugu Copyright", @"HelpMenu",
                            @"Fugu Copyright" ) ] ) {
            path = [[ NSBundle mainBundle ] pathForResource: @"COPYRIGHT"
                                                        ofType: @"txt" ];
        }
        
        launcher = [[ UMFileLauncher alloc ] init ];
        [ launcher openFile: path withApplication: nil ];
        [ launcher release ];
    }
}

- ( void )awakeFromNib
{
    NSUserDefaults	*defaults;
    NSString		*hdir, *identifier;
    NSArray		*columnArray;
    SFTPItemCell	*cell;
    NSFont              *logFont = nil;
    int			i, count;

    /* get images for display */
    dirImage = [[[ NSWorkspace sharedWorkspace ] iconForFileType: @"'fldr'" ] retain ];
    [ dirImage setScalesWhenResized: YES ];
    [ dirImage setSize: NSMakeSize( 16.0, 16.0 ) ];
    fileImage = [[[ NSWorkspace sharedWorkspace ] iconForFileType: @"'doc '" ] retain ];
    [ fileImage setScalesWhenResized: YES ];
    [ fileImage setSize: NSMakeSize( 16.0, 16.0 ) ];
    linkImage = [[ NSImage imageNamed: @"symlink" ] retain ];
    
    [ localBox setContentView: localView ];
    [ localView setNeedsDisplay: YES ];
    [ remoteBox setContentView: loginView ];
    [ loginView setNeedsDisplay: YES ];
    [ logField setEditable: NO ];
    
    if ( [ mainWindow setTitleToLocalHostName ] < 0 ) {
        [ logField insertText: @"Could not get hostname. Using default name \"localhost.\"" ];
    }
    [ mainWindow setFrameUsingName: @"SFTPWindow" ];
    [ mainWindow setFrameAutosaveName: @"SFTPWindow" ];
    
    [ imagePreviewPanel setFrameUsingName: @"ImagePreviewPanel" ];
    [ imagePreviewPanel setFrameAutosaveName: @"ImagePreviewPanel" ];
    
    [ infoPanel setFrameUsingName: @"InfoPanel" ];
    [ infoPanel setFrameAutosaveName: @"InfoPanel" ];
    
    [ logField setString: @"" ];
    if (( logFont = [ NSFont fontWithName: @"Courier" size: 9 ] ) == nil ) {
        logFont = [ NSFont systemFontOfSize: 9 ];
    }
    if ( logFont != nil ) {
        [ logField setFont: logFont ];
    }
    
    [ manualComField registerForDraggedTypes:
                [ NSArray arrayWithObject: NSFilenamesPboardType ]];
    
    [ localBrowser setAction: nil ];//@selector( localBrowserSingleClick: ) ];
    [ localBrowser setDoubleAction: @selector( localBrowserDoubleClick: ) ];
    [ localBrowser setAutosaveTableColumns: YES ];
    [ localBrowser setNextKeyView: remoteHost ];
    [ loginDirField setNextKeyView: localBrowser ];
    [ localBrowser setAllowsColumnSelection: NO ];
    
    [ remoteBrowser setAction: nil ];//@selector( remoteBrowserSingleClick: ) ];
    [ remoteBrowser setDoubleAction: @selector( remoteBrowserDoubleClick: ) ];
    [ remoteBrowser setAutosaveTableColumns: YES ];
    [ remoteBrowser setNextKeyView: localBrowser ];
    [ remoteBrowser setAllowsColumnSelection: NO ];
    
    [ remoteHost setStringValue: @"" ];
    [ remoteHost setAction: nil ];	/* don't intercept 'return' presses */
    
    [ remoteHost setCompletes: YES ];
    [ addToFavButton setEnabled: NO ];
    [ popUpFavs removeAllItems ];
    [ remoteProgBar retain ];
    [ remoteProgBar removeFromSuperview ];
    
    remoteHistoryMenu = [[ NSMenu alloc ] init ];
    localHistoryMenu = [[ NSMenu alloc ] init ];
    
    /*	set up visible table columns */
    while ( [[ localBrowser tableColumns ] count ] > 1 ) {
        [ localBrowser removeTableColumn:
                [[ localBrowser tableColumns ] lastObject ]];
    }
    while ( [[ remoteBrowser tableColumns ] count ] > 1 ) {
        [ remoteBrowser removeTableColumn:
                [[ remoteBrowser tableColumns ] lastObject ]];
    }
    
    columnArray = [[ NSUserDefaults standardUserDefaults ]
                        objectForKey: @"VisibleColumns" ];
    
    if ( columnArray == nil ) {
        columnArray = [ NSArray arrayWithObjects:
                            [ NSDictionary dictionaryWithObjectsAndKeys:
                                    @"sizecolumn", @"identifier",
                    [ NSNumber numberWithFloat: SIZE_COLUMN_WIDTH ], @"width", nil ],
                            [ NSDictionary dictionaryWithObjectsAndKeys:
                                    @"datecolumn", @"identifier",
                    [ NSNumber numberWithFloat: DATE_COLUMN_WIDTH ], @"width", nil ], nil ];
        [[ NSUserDefaults standardUserDefaults ] setObject: columnArray
                                                forKey: @"VisibleColumns" ];
    }

    count = [ columnArray count ];
    
    for ( i = 0; i < count; i++ ) {
        id			o;
        NSString		*identifier = @"", *title = @"column";
        float			width = 0.0;
        
        o = [ columnArray objectAtIndex: i ];
        
        if ( [ o isKindOfClass: [ NSString class ]] ) {
            identifier = o;
        } else if ( [ o isKindOfClass: [ NSDictionary class ]] ) {
            identifier = [ o objectForKey: @"identifier" ];
        }

        title = ColumnTitleFromIdentifier( identifier );
        width = [[[ columnArray objectAtIndex: i ]
                        objectForKey: @"width" ] floatValue ];

        [ self setMenuOnStateForColumnWithIdentifier: identifier ];
        
        [ localBrowser addTableColumnWithIdentifier: identifier
                columnTitle: title width: width ];
        [ remoteBrowser addTableColumnWithIdentifier: identifier
                columnTitle: title width: width ];
    }
    [ localBrowser sizeLastColumnToFit ];
    [ remoteBrowser sizeLastColumnToFit ];
    
    identifier = [[ NSUserDefaults standardUserDefaults ]
                    objectForKey: @"RemoteBrowserSortingIdentifier" ];
    if ( identifier == nil ) {
        identifier = @"namecolumn";
        [[ NSUserDefaults standardUserDefaults ]
                    setObject: identifier
                    forKey: @"RemoteBrowserSortingIdentifier" ];
        [[ NSUserDefaults standardUserDefaults ]
                    setObject: [ NSNumber numberWithInt: 0 ]
                    forKey: @"RemoteBrowserSortDirection" ];
    }
    if ( identifier != nil ) {
        NSTableColumn		*tc = nil;
        NSArray			*a = [ remoteBrowser tableColumns ];
        int			sortdirection = 0;
        
        for ( i = 0; i < [ a count ]; i++ ) {
            if ( [[[ a objectAtIndex: i ] identifier ]
                            isEqualToString: identifier ] ) {
                tc = [ a objectAtIndex: i ];
                break;
            }
        }
        
        if ( tc != nil ) {
            NSImage		*image = nil;
            
            [ remoteBrowser setHighlightedTableColumn: tc ];
            sortdirection = [[[ NSUserDefaults standardUserDefaults ]
                                objectForKey: @"RemoteBrowserSortDirection" ]
                                intValue ];
            
            if ( sortdirection == 0 ) {
                image = [ NSImage imageNamed: @"NSAscendingSortIndicator" ];
            } else {
                image = [ NSImage imageNamed: @"NSDescendingSortIndicator" ];
            }
            [ remoteBrowser setIndicatorImage: image inTableColumn: tc ];
        }
    }
                    
    
    /* set type of cell for tables */
    cell = [[ SFTPItemCell alloc ] init ];
    [ cell setAction: nil ];
    [[[ localBrowser tableColumns ]
            objectAtIndex: 0 ]
            setDataCell: cell ];
    [[[ remoteBrowser tableColumns ]
            objectAtIndex: 0 ]
            setDataCell: cell ];
    [ cell release ];
                        
    [ localBrowser registerForDraggedTypes:
            [ NSArray arrayWithObjects: NSFileContentsPboardType, nil ]];
    [ localBrowser setDataSource: self ];
    localDirPath = [[ NSString alloc ] init ];
    localDirContents = [[ NSMutableArray alloc ] init ];
    dotlessLDir = [[ NSMutableArray alloc ] init ];
    remoteDirContents = [[ NSMutableArray alloc ] init ];
    
    rSwitchArray = [[ NSArray alloc ] initWithObjects:
                    roReadSwitch, roWriteSwitch, roExecSwitch,
                    rgReadSwitch, rgWriteSwitch, rgExecSwitch,
                    raReadSwitch, raWriteSwitch, raExecSwitch, nil ];
                    
    [ remoteBrowser registerForDraggedTypes:
                [ NSArray arrayWithObject: NSFilenamesPboardType ]];
    [ remoteBrowser setDataSource: self ];
    [ remoteBrowser reloadData ];
    
    /* set self to info tab's delegate */
    [ infoTabView setDelegate: self ];
        
    /* get defaults from prefs */
    defaults = [ NSUserDefaults standardUserDefaults ];
    hdir = [ defaults objectForKey: @"defaultdir" ];
    if ( hdir == nil || ! [ hdir length ] ) hdir = NSHomeDirectory();
    [ self localBrowserReloadForPath: hdir ];
        
    [ remoteHost addItemsWithObjectValues: [ defaults objectForKey: @"RecentServers" ]];
    
    if ( [ defaults objectForKey: @"PostEditBehaviour" ] == nil ) {
        [ defaults setObject: [ NSNumber numberWithInt: 0 ]
                    forKey: @"PostEditBehaviour" ];
    }
    
    /* get favorites from prefs */
    [ self reloadDefaults ];
    
    [ self toolbarSetup ];
    
    /* search for rendezvous-enabled ssh servers */
    [ rendezvousPopUp setEnabled: NO ];
    
    if ( [ NSWorkspace systemVersion ] >= 0x00001023 ) {
        [[ rendezvousPopUp itemAtIndex: 0 ] setImage: [ NSImage imageNamed: @"zeroconf.png" ]];
        [ self scanForSSHServers: nil ];
    } else {
        NSLog( @"system doesn't support rendezvous, disabling." );
    }
}

- ( IBAction )toggleDots: ( id )sender
{
    if ( ! dotflag ) {
        dotflag = 1;
    } else {
        dotflag = 0;
    }
    [ localBrowser reloadData ];

    if ( connected ) {
        [ remoteBrowser reloadData ];
    }
}

- ( IBAction )toggleGroupColumn: ( id )sender
{
    int			state = [ sender state ];
    
    if ( state == NSOnState ) {
        [ sender setState: NSOffState ];
        [ localBrowser removeTableColumn:
                [ localBrowser tableColumnWithIdentifier: @"groupcolumn" ]];
        [ remoteBrowser removeTableColumn:
                [ remoteBrowser tableColumnWithIdentifier: @"groupcolumn" ]];
    } else {
        NSString	*identifier = @"groupcolumn";
        NSString	*title = ColumnTitleFromIdentifier( identifier );
        
        [ localBrowser addTableColumnWithIdentifier: identifier
            columnTitle: title width: GROUP_COLUMN_WIDTH ];
        [ remoteBrowser addTableColumnWithIdentifier: identifier
            columnTitle: title width: GROUP_COLUMN_WIDTH ];
        [ localBrowser moveColumn: ( [ localBrowser numberOfColumns ] - 1 )
                        toColumn: 1 ];
        [ remoteBrowser moveColumn: ( [ remoteBrowser numberOfColumns ] - 1 )
                        toColumn: 1 ];
                                        
        [ sender setState: NSOnState ];
    }
}

- ( IBAction )toggleModDateColumn: ( id )sender;
{
    int			state = [ sender state ];
    
    if ( state == NSOnState ) {
        [ sender setState: NSOffState ];
        [ localBrowser removeTableColumn:
                [ localBrowser tableColumnWithIdentifier: @"datecolumn" ]];
        [ remoteBrowser removeTableColumn:
                [ remoteBrowser tableColumnWithIdentifier: @"datecolumn" ]];
    } else {
        NSString	*identifier = @"datecolumn";
        NSString	*title = ColumnTitleFromIdentifier( identifier );
        
        [ localBrowser addTableColumnWithIdentifier: identifier
            columnTitle: title width: DATE_COLUMN_WIDTH ];
        [ remoteBrowser addTableColumnWithIdentifier: identifier
            columnTitle: title width: DATE_COLUMN_WIDTH ];
        [ localBrowser moveColumn: ( [ localBrowser numberOfColumns ] - 1 )
                        toColumn: 1 ];
        [ remoteBrowser moveColumn: ( [ remoteBrowser numberOfColumns ] - 1 )
                        toColumn: 1 ];
                                        
        [ sender setState: NSOnState ];
    }
}

- ( IBAction )toggleModeColumn: ( id )sender
{
    int			state = [ sender state ];
    
    if ( state == NSOnState ) {
        [ sender setState: NSOffState ];
        [ localBrowser removeTableColumn:
                [ localBrowser tableColumnWithIdentifier: @"permcolumn" ]];
        [ remoteBrowser removeTableColumn:
                [ remoteBrowser tableColumnWithIdentifier: @"permcolumn" ]];
    } else {
        NSString	*identifier = @"permcolumn";
        NSString	*title = ColumnTitleFromIdentifier( identifier );
        
        [ localBrowser addTableColumnWithIdentifier: identifier
            columnTitle: title width: MODE_COLUMN_WIDTH ];
        [ remoteBrowser addTableColumnWithIdentifier: identifier
            columnTitle: title width: MODE_COLUMN_WIDTH ];
        [ localBrowser moveColumn: ( [ localBrowser numberOfColumns ] - 1 )
                        toColumn: 1 ];
        [ remoteBrowser moveColumn: ( [ remoteBrowser numberOfColumns ] - 1 )
                        toColumn: 1 ];
                                        
        [ sender setState: NSOnState ];
    }
}

- ( IBAction )toggleOwnerColumn: ( id )sender
{
    int			state = [ sender state ];
    
    if ( state == NSOnState ) {
        [ sender setState: NSOffState ];
        [ localBrowser removeTableColumn:
                [ localBrowser tableColumnWithIdentifier: @"ownercolumn" ]];
        [ remoteBrowser removeTableColumn:
                [ remoteBrowser tableColumnWithIdentifier: @"ownercolumn" ]];
    } else {
        NSString	*identifier = @"ownercolumn";
        NSString	*title = ColumnTitleFromIdentifier( identifier );
        
        [ localBrowser addTableColumnWithIdentifier: identifier
            columnTitle: title width: OWNER_COLUMN_WIDTH ];
        [ remoteBrowser addTableColumnWithIdentifier: identifier
            columnTitle: title width: OWNER_COLUMN_WIDTH ];
        [ localBrowser moveColumn: ( [ localBrowser numberOfColumns ] - 1 )
                        toColumn: 1 ];
        [ remoteBrowser moveColumn: ( [ remoteBrowser numberOfColumns ] - 1 )
                        toColumn: 1 ];
                                        
        [ sender setState: NSOnState ];
    }
}

- ( IBAction )toggleSizeColumn: ( id )sender
{
    int			state = [ sender state ];
    
    if ( state == NSOnState ) {
        [ sender setState: NSOffState ];
        [ localBrowser removeTableColumn:
                [ localBrowser tableColumnWithIdentifier: @"sizecolumn" ]];
        [ remoteBrowser removeTableColumn:
                [ remoteBrowser tableColumnWithIdentifier: @"sizecolumn" ]];
    } else {
        NSString	*identifier = @"sizecolumn";
        NSString	*title = ColumnTitleFromIdentifier( identifier );
        
        [ localBrowser addTableColumnWithIdentifier: identifier
            columnTitle: title width: SIZE_COLUMN_WIDTH ];
        [ remoteBrowser addTableColumnWithIdentifier: identifier
            columnTitle: title width: SIZE_COLUMN_WIDTH ];
        [ localBrowser moveColumn: ( [ localBrowser numberOfColumns ] - 1 )
                        toColumn: 1 ];
        [ remoteBrowser moveColumn: ( [ remoteBrowser numberOfColumns ] - 1 )
                        toColumn: 1 ];
                                        
        [ sender setState: NSOnState ];
    }
}

- ( IBAction )cancelConnection: ( id )sender
{
    int			rc;
    
    if ( [ uploadQueue count ] ) {
	rc = NSRunAlertPanel( NSLocalizedString( @"Warning: Upload queue not empty.",
                                    @"Warning: Upload queue not empty." ),
                        NSLocalizedString( @"There are %d items left in the "
                                    @"upload queue. Cancelling will end this session. Do "
                                    @"you want to disconnect without uploading all of them?",
                                    @"There are %d items left in the "
                                    @"upload queue. Cancelling will end this session. Do "
                                    @"you want to disconnect without uploading all of them?" ),
                        NSLocalizedString( @"Disconnect", @"Disconnect" ),
                        NSLocalizedString( @"Cancel", @"Cancel" ), @"", [ uploadQueue count ] );
        
        switch( rc ) {
        case NSAlertDefaultReturn:
            [ uploadQueue removeAllObjects ];
            break;
        default:
        case NSAlertAlternateReturn:
            return;
        }
    }
    
    [ downloadQueue removeAllObjects ];
    
    if ( [ uploadProgPanel isVisible ] )
        [ self updateUploadProgress: 1 ];
    
    if ( [ downloadSheet isVisible ] )
        [ self finishedDownload ];
    
    [ logField insertText: @"\nCaught request to cancel connection. Ending....\n" ];
    cancelflag = 1;
    
    if ( [ verifyConnectSheet isVisible ] ) {
        if ( write( master, "no\n", strlen( "no\n" )) != strlen( "no\n" )) {
            NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
                    NSLocalizedString( @"Write failed: Did not write correct number of bytes!",
                                    @"Write failed: Did not write correct number of bytes!" ),
                    NSLocalizedString( @"Quit", @"Quit" ), @"", @"" );
            exit( 2 );
        }            
        [ verifyConnectSheet orderOut: nil ];
        [ NSApp endSheet: verifyConnectSheet ];
    }
    
    if ( [ mainWindow setTitleToLocalHostName ] < 0 ) {
        [ logField insertText: @"Could not get hostname. Using default name \"localhost.\"" ];
    }
    
    if ( ! connected && ! connecting ) return;
    
    if ( sftppid > 0 ) {
        if ( kill( sftppid, SIGINT ) != 0 ) {
            if ( errno == ESRCH ) NSLog( @"kill: sftp process %d: %s", sftppid, strerror( errno ));
        } else {
            [ logField insertText:
                [ NSString stringWithFormat: @"sftp process with pid %d killed.\n", sftppid ]];
            connecting = 0;
            connected = 0;
        }
    }
    [ remoteBox setContentView: nil ];
    [ remoteBox setContentView: loginView ];
    [ connectButton setEnabled: YES ];
}

- ( IBAction )continueConnecting: ( id )sender
{
    [ verifyConnectSheet orderOut: nil ];
    [ NSApp endSheet: verifyConnectSheet ];
    
    [ self writeCommand: "yes" ];
}

- ( void )reloadDefaults
{
    int			i;
    id			dobj, fobj;
    struct passwd	*pw;
    NSArray		*favs;
    NSUserDefaults	*defaults = [ NSUserDefaults standardUserDefaults ];
    
    /* reload favorites from prefs */
    [ popUpFavs removeAllItems ];
    favs = [ defaults objectForKey: @"Favorites" ];
    [ popUpFavs addItemWithTitle: @"" ];
    [[ popUpFavs itemAtIndex: 0 ] setImage: [ NSImage imageNamed: @"favorites.png" ]];
    for ( i = 0; i < [ favs count ]; i++ ) {
        fobj = [ favs objectAtIndex: i ];
        if ( [ fobj isKindOfClass: [ NSString class ]] ) {
            if ( [ fobj isEqualToString: @"" ] ) continue;
            [ popUpFavs addItemWithTitle: fobj ];
        } else {
            NSString	*title = nil;
            if ( [ fobj objectForKey: @"nick" ] != nil &&
                    ! [[ fobj objectForKey: @"nick" ] isEqualToString: @"" ] ) {
                title = [ fobj objectForKey: @"nick" ];
            } else if ( [ fobj objectForKey: @"host" ] != nil &&
                    ! [[ fobj objectForKey: @"host" ] isEqualToString: @"" ] ) {
                title = [ fobj objectForKey: @"host" ];
            } else {
                continue;
            }
            [ popUpFavs addItemWithTitle: title ];
        }
        [[ popUpFavs lastItem ] setImage: [ NSImage imageNamed: @"favorites.png" ]];
    }

    /* don't change things if user's entered anything */
    if ( [[ remoteHost stringValue ] length ] ) return;
    
    if (( dobj = [ defaults objectForKey: @"defaultuser" ] ) != nil ) {
        [ userName setStringValue: dobj ];
    } else if (( pw = getpwuid( getuid())) != NULL ) {
        [ userName setStringValue: [ NSString stringWithUTF8String: pw->pw_name ]];
    }
    if (( dobj = [ defaults objectForKey: @"defaulthost" ] ) != nil ) {
        [ remoteHost setStringValue: dobj ];
    }
    if (( dobj = [ defaults objectForKey: @"defaultport" ] ) != nil ) {
        [ portField setStringValue: dobj ];
    }
    if (( dobj = [ defaults objectForKey: @"defaultrdir" ] ) != nil ) {
        [ loginDirField setStringValue: dobj ];
    }
}

- ( IBAction )refreshBrowsers: ( id )sender
{
    [ self localBrowserReloadForPath: localDirPath ];
    if ( !connected ) return;
    [ self getListing ];
}

- ( void )loadRemoteBrowserWithItems: ( NSArray * )items
{
    int			sorting;
    int			selectedrow = [ remoteBrowser selectedRow ];
    BOOL		asciisort = [[ NSUserDefaults standardUserDefaults ]
                                            boolForKey: @"ASCIIOrderSorting" ];

    [ remoteDirContents removeAllObjects ];
    [ dotlessRDir removeAllObjects ];
    
    [ remoteDirContents setArray: items ];
    
    if ( asciisort ) {
        sorting = NSLiteralSearch;
    } else {
        sorting = NSCaseInsensitiveSearch;
    }
    
    [ remoteDirContents sortUsingFunction:
            sortFunctionForIdentifier( [[ remoteBrowser highlightedTableColumn ]
                                            identifier ] )
                        context: ( void * )&sorting ];
                        
    if ( [[[ NSUserDefaults standardUserDefaults ]
            objectForKey: @"RemoteBrowserSortDirection" ] intValue ] ) {
        [ remoteDirContents reverse ];
    }
    [ dotlessRDir addObjectsFromArray: [ remoteDirContents visibleItems ]];

    [ remoteBrowser reloadData ];
    
    [ remoteBrowser scrollRowToVisible: 0 ];
    [ remoteMsgField setStringValue: @"" ];
    [ remoteProgBar stopAnimation: nil ];
    [ remoteProgBar retain ];
    [ remoteProgBar removeFromSuperview ];
    if ( ![[ remoteColumnFooter stringValue ] length ] ) {
        [ remoteColumnFooter setStringValue: [ remoteHost stringValue ]];
    }
    
    if ( [ infoPanel isVisible ] ) {
	if ( selectedrow >= 0 ) {
	    [ remoteBrowser selectRow: selectedrow byExtendingSelection: NO ];
	    [ self getInfo: nil ];
	}
    }
}

- ( void )setRemotePathPopUp: ( NSString * )pwd
{
    int			i;
    NSMutableArray	*rPathComponents = [[ NSMutableArray alloc ] init ];
    NSArray		*tmp = [[ pwd componentsSeparatedByString: @"/" ] copy ];
    NSImage		*slashImage;
    NSMenuItem		*item;

    [ remoteDirPath release ];
    remoteDirPath = [ pwd copy ];
    
    if ( remoteHome == nil ) {
        char		*p;

NSLog( @"setting home directory" );
        p = strchr(( char * )[ pwd UTF8String ], '/' );
        for ( i = 0; i < strlen( p ); i++ ) {
            if ( p[ i ] == '\r' ) p[ i ] = '\0';
        }
        if ( p != NULL ) remoteHome = [[ NSString stringWithUTF8String: p ] retain ];
    }
    
    for ( i = ([ tmp count ] - 1 ); i > 0; i-- ) {
        if ( [[ tmp objectAtIndex: i ] isEqualToString: @"" ] ) continue;
        [ rPathComponents addObject: [ tmp objectAtIndex: i ]];
    }
    [ tmp release ];
    
    [ rPathPopUp removeAllItems ];
    [ rPathComponents addObject: @"/" ];
    for ( i = 0; i < [ rPathComponents count ]; i++ ) {
        item = [[ NSMenuItem alloc ] initWithTitle: [ rPathComponents objectAtIndex: i ]
                                        action: NULL
                                        keyEquivalent: @"" ];
        [ item setImage: dirImage ];
        [[ rPathPopUp menu ] addItem: item ];
        [ item release ];
    }
    slashImage = [[ NSWorkspace sharedWorkspace ] iconForFile: @"/" ];
    [ slashImage setSize: NSMakeSize( 16, 16 ) ];
    [[ rPathPopUp lastItem ] setImage: slashImage ];
    [ rPathPopUp selectItemWithTitle: [ rPathComponents objectAtIndex: 0 ]];
    [ rPathComponents release ];
    
    /* setup remote history menu; don't add path if we're reloading */
    if ( [ remoteHistoryMenu numberOfItems ] == 0
            || ! [ remoteDirPath isEqualToString: [[ remoteHistoryMenu itemAtIndex: 0 ] title ]] ) {
        NSImage			*img = dirImage;
        
        if ( [ remoteDirPath isEqualToString: @"/" ] ) {
            img = nil;
            img = slashImage;
        }
        [ remoteHistoryMenu insertItemWithTitle: remoteDirPath
                            action: @selector( cdFromRemoteHistoryMenu: )
                            keyEquivalent: @""
                            atIndex: 0 ];
        [[ remoteHistoryMenu itemAtIndex: 0 ] setImage: img ];
        while ( [ remoteHistoryMenu numberOfItems ] > 20 ) {
            [ remoteHistoryMenu removeItemAtIndex: ( [ remoteHistoryMenu numberOfItems ] - 1 ) ];
        }
    }
    
    /* close the preview panel, if open */
    if ( [ imagePreviewPanel isVisible ] ) {
        [ imagePreviewPanel close ];
    }
}

- ( void )showRemoteFiles
{
    char		*cdcmd, *dpath;
    char		*quote = "\"";
    
    [ remoteBox setContentView: nil ];
    [ remoteBox setContentView: remoteView ];
    
    if ( [[ loginDirField stringValue ] length ] ) {
        dpath = ( char * )[[ loginDirField stringValue ] UTF8String ];
    } else {
        dpath = ".";
    }
    
    if ( strchr(( char * )dpath, '"' ) != NULL ) {
        quote = NULL;
        quote = "\'";
    } else if ( strchr(( char * )dpath, '\'' ) != NULL ) {
        quote = NULL;
        quote = "\"";
    }
    
    cdcmd = ( char * )[[ NSString stringWithFormat:
                        @"cd %s%s%s", quote, dpath, quote ] UTF8String ];
    
    [ commandButton setEnabled: YES ];
    connecting = 0;
    connected = 1;
    
    [[ remoteBrowser window ] makeFirstResponder: remoteBrowser ];
    [ localBrowser setNextKeyView: remoteBrowser ];
    [ self writeCommand: cdcmd ];
}

- ( void )getListing
{
    [ self setBusyStatusWithMessage:
            NSLocalizedString( @"Requesting file listing from server....",
                                @"Requesting file listing from server...." ) ];
    [ self writeCommand: lsform ];
}

- ( void )setBusyStatusWithMessage: ( NSString * )message
{
    [[ mainWindow contentView ] addSubview: remoteProgBar ];
    [ remoteProgBar setUsesThreadedAnimation: YES ];
    [ remoteProgBar startAnimation: nil ];
    [ remoteMsgField setStringValue: message ];
    /* disable all buttons while waiting for command to finish */
    [ commandButton setEnabled: NO ];
    [ rPathPopUp setEnabled: NO ];
    [ lPathPopUp setEnabled: NO ];
}

- ( void )finishedCommand
{
    /* enable buttons on completion */
    [ commandButton setEnabled: YES ];
    [ rPathPopUp setEnabled: YES ];
    [ lPathPopUp setEnabled: YES ];
    [ remoteProgBar retain ];
    [ remoteProgBar removeFromSuperview ];

    [ self writeCommand: "pwd" ];
}

- ( void )writeCommand: ( void * )cmd
{
    int		wr;
    
    if (( wr = write( master, cmd, strlen( cmd ))) != strlen( cmd )) goto WRITE_ERR;
    if (( wr = write( master, "\n", strlen( "\n" ))) != strlen( "\n" )) goto WRITE_ERR;
    
    return;
    
WRITE_ERR:
    NSRunAlertPanel( NSLocalizedString(
                @"Write failed: Did not write correct number of bytes!",
                @"Write failed: Did not write correct number of bytes!" ),
        @"", @"Exit", @"", @"" );
    exit( 2 );
}

- ( IBAction )sendManualCommand: ( id )sender
{
    [ self writeCommand: ( char * )[[ manualComField stringValue ] UTF8String ]];
    [ manualComField selectText: nil ];
}

- ( IBAction )disconnect: ( id )sender
{
    int		rc;
    
    if ( [[ self editedDocuments ] count ] ) {
	rc = NSRunAlertPanel(
		NSLocalizedString( @"Warning: Some remote documents are still being edited.",
			    @"Warning: Some remote documents are still being edited." ),
		NSLocalizedString( @"If you disconnect now, "
			    @"you will lose any unsaved changes. Are you sure you want to disconnect?",
			    @"If you disconnect now, "
			    @"you will lose any unsaved changes. Are you sure you want to disconnect?" ),
		NSLocalizedString( @"Disconnect", @"Disconnect" ),
		NSLocalizedString( @"Cancel", @"Cancel" ), @"", [[ self editedDocuments ] count ] );
		
	switch ( rc ) {
	case NSAlertDefaultReturn:
	    [ editedDocuments removeAllObjects ];
	    break;
	    
	case NSAlertAlternateReturn:
	default:
	    return;
	}
    }
    
    if ( [ mainWindow setTitleToLocalHostName ] < 0 ) {
        [ logField insertText: @"Could not get hostname. Using default name \"localhost.\"" ];
    }
    
    if ( connected ) {
        [ self writeCommand: "quit" ];
    }
    
    if ( [ self cachedPreviews ] != nil ) {
        [ cachedPreviews release ];
        cachedPreviews = nil;
    }
    
    [ localBrowser setNextKeyView: remoteHost ];
}

- ( void )cleanUp
{
    int		i;
    
    [ uploadQueue removeAllObjects ];
    if ( [ rPathPopUp numberOfItems ] ) {
        [[ rPathPopUp itemAtIndex: 0 ] setImage: nil ];
    }
    [ rPathPopUp removeAllItems ];
    for ( i = [ remoteHistoryMenu numberOfItems ]; i > 0; i-- ) {
        [ remoteHistoryMenu removeItemAtIndex: 0 ];
    }
    
    /* disable buttons */
    [ commandButton setEnabled: NO ];
    
    [ remoteDirContents removeAllObjects ];
    [ dotlessRDir removeAllObjects ];
    [ remoteBrowser reloadData ];
    [ remoteColumnFooter setStringValue: @"" ];
    
    [ connectButton setEnabled: YES ];
    [[ localBrowser window ] makeFirstResponder: localBrowser ];
    [ remoteBox setContentView: nil ];
    [ remoteBox setContentView: loginView ];
    [[ remoteHost window ] makeFirstResponder: remoteHost ];
    [ passErrorField setStringValue: @"" ];
    
    remoteHome = nil;
    cancelflag = 0;
    [ self setGotPasswordFromKeychain: NO ];
    [ addToKeychainSwitch setState: NSOffState ];
    if ( [ infoPanel isVisible ] ) [ infoPanel close ];
}

- ( void )changeToRemoteDirectory: ( NSString * )remotePath
{
    char                cdcmd[ MAXPATHLEN * 2 ] = { 0 };
    
    if ( remotePath == nil ) {
        NSBeep();
        return;
    }
    
    if ( snprintf( cdcmd, MAXPATHLEN, "cd \"%s\"", [ remotePath UTF8String ] )
            >= MAXPATHLEN ) {
        NSBeep();
        NSLog( @"cd \"%@\": too long", remotePath );
        return;
    }

    [ self writeCommand: cdcmd ];
    while ( ! [ tServer atSftpPrompt ] ) ;
    [ self writeCommand: lsform ];
}

- ( void )localBrowserReloadForPath: ( NSString * )path
{
    int			i, sorting, sortdirection = 0;
    NSArray		*bits;
    NSString		*fullpath, *componentpath, *identifier;
    NSMutableArray	*tmp, *lpath;
    NSImage		*img;
    NSMenuItem		*item;
    SFTPNode		*node;
    
    fullpath = [ path stringByExpandingTildeInPath ];

    if ( access(( char * )[ fullpath UTF8String ], F_OK | R_OK | X_OK ) < 0 ) {
        NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
                NSLocalizedString( @"Couldn't view %@: %s",
                        @"Couldn't view %@: %s" ),
                NSLocalizedString( @"OK", @"OK" ), @"", @"",
                fullpath, strerror( errno ));
        return;
    }
    
    if ( localDirPath != nil ) {
        [ localDirPath release ];
        localDirPath = nil;
    }
    localDirPath = [ fullpath copy ];
    lpath = [[ NSMutableArray alloc ] init ];
    [ fullpath retain ];
    
    /* setup path popup button */
    bits = [ fullpath componentsSeparatedByString: @"/" ];
    
    for ( i = ( [ bits count ] - 1 ); i > 0; i-- ) {
        if ( ! [ ( NSString * )[ bits objectAtIndex: i ] length ] ) continue;
        [ lpath addObject: [ bits objectAtIndex: i ]];
    }
    
    [ lpath addObject: @"/" ];
    [ lPathPopUp removeAllItems ];
    
    componentpath = fullpath;
    
    for ( i = 0; i < [ lpath count ]; i++ ) {
        img = [[ NSWorkspace sharedWorkspace ] iconForFile: componentpath ];
                                    
        [ img setScalesWhenResized: YES ];
        [ img setSize: NSMakeSize( 16.0, 16.0 ) ];
        
        item = [[ NSMenuItem alloc ] initWithTitle: [ lpath objectAtIndex: i ]
                                        action: NULL
                                        keyEquivalent: @"" ];
        [ item setImage: img ];
        [[ lPathPopUp menu ] addItem: item ];
        [ item release ];
        img = nil;
        componentpath = [ componentpath stringByDeletingLastPathComponent ];
    }
    img = [[ NSWorkspace sharedWorkspace ] iconForFile: @"/" ];
    [ img setSize: NSMakeSize( 16, 16 ) ];
    [[ lPathPopUp lastItem ] setImage: img ];
    [ lPathPopUp selectItemWithTitle: [ lpath objectAtIndex: 0 ]];
    [ lpath release ];
    
    /* add path to history menu; don't add if we're reloading */
    if ( [ localHistoryMenu numberOfItems ] == 0
                || ! [ fullpath isEqualToString: [[ localHistoryMenu itemAtIndex: 0 ] title ]] ) {
        [ localHistoryMenu insertItemWithTitle: fullpath
                            action: @selector( cdFromLocalHistoryMenu: )
                            keyEquivalent: @""
                            atIndex: 0 ];
        img = nil;
        img = [[ NSWorkspace sharedWorkspace ] iconForFile: fullpath ];
        [ img setSize: NSMakeSize( 16, 16 ) ];
        [[ localHistoryMenu itemAtIndex: 0 ] setImage: img ];
        while ( [ localHistoryMenu numberOfItems ] > 20 ) {
            [ localHistoryMenu removeItemAtIndex: ( [ localHistoryMenu numberOfItems ] - 1 ) ];
        }
    }
    
    [ localDirContents release ];
    localDirContents = nil;
    
    [ dotlessLDir removeAllObjects ];
    
    if (( identifier = [[ NSUserDefaults standardUserDefaults ]
                objectForKey: @"LocalBrowserSortingIdentifier" ] ) == nil ) {
        identifier = @"namecolumn";
        [[ NSUserDefaults standardUserDefaults ]
                setObject: identifier
                forKey: @"LocalBrowserSortingIdentifier" ];
    }
    sortdirection = [[[ NSUserDefaults standardUserDefaults ]
                        objectForKey: @"LocalBrowserSortDirection" ]
                        intValue ];
    
    if ( ! [[[ localBrowser highlightedTableColumn ]
                identifier ] isEqualToString: identifier ] ) {
        NSArray			*a = [ localBrowser tableColumns ];
        
        for ( i = 0; i < [ a count ]; i++ ) {
            if ( [[[ a objectAtIndex: i ] identifier ]
                        isEqualToString: identifier ] ) {
                break;
            }
        }
        [ localBrowser setHighlightedTableColumn: [ a objectAtIndex: i ]];
        [ localBrowser setIndicatorImage:
                [ NSImage imageNamed: @"NSAscendingSortIndicator" ]
                        inTableColumn: [ a objectAtIndex: i ]];
    }
    
    sorting = ( int )[[ NSUserDefaults standardUserDefaults ]
                            boolForKey: @"ASCIIOrderSorting" ];
    
    if ( sorting ) {
        sorting = NSLiteralSearch;
    } else {
        sorting = NSCaseInsensitiveSearch;
    }
    
    node = [[ SFTPNode alloc ] init ];
    tmp = [ node itemsAtPath: fullpath showHiddenFiles: YES ];
    localDirContents = [ tmp mutableCopy ];
    [ localDirContents
            sortUsingFunction: sortFunctionForIdentifier( identifier )
            context: ( void * )&sorting ];
    if ( sortdirection ) {
        [ localDirContents reverse ];
        [ localBrowser setIndicatorImage:
                [ NSImage imageNamed: @"NSDescendingSortIndicator" ]
                inTableColumn: [ localBrowser highlightedTableColumn ]];
    }
        
    [ dotlessLDir addObjectsFromArray: [ localDirContents visibleItems ]];
    
    [ node release ];
    [ fullpath release ];

    [ localBrowser reloadData ];
}

- ( IBAction )localBrowserSingleClick: ( id )browser
{
    if ( [ infoPanel isVisible ] ) [ self getInfo: nil ];
}

- ( void )changeDirectory: ( id )sender
{
    if ( [[ mainWindow firstResponder ] isEqual: localBrowser ] && [ localBrowser selectedRow ] >= 0 ) {
        [ self localBrowserDoubleClick: nil ];
    } else if ( [[ mainWindow firstResponder ] isEqual: remoteBrowser ] && connected ) {
        [ self remoteBrowserDoubleClick: nil ];
    }
}

- ( void )dotdot: ( id )sender
{
    if ( [[ mainWindow firstResponder ] isEqual: localBrowser ] ) {
        [ self localCdDotDot: nil ];
    } else if ( [[ mainWindow firstResponder ] isEqual: remoteBrowser ] && connected ) {
        [ self remoteCdDotDot: nil ];
    }
}

- ( IBAction )localBrowserDoubleClick: ( id )browser
{
    int			row = [ localBrowser clickedRow ];
    NSDictionary	*dict;
    NSString		*type, *path;
    
    if ( row < 0 ) {
        if (( row = [ localBrowser selectedRow ] ) < 0 ) {
            NSBeep();
            return;
        }
    }

    if ( !dotflag ) {
        dict = [ dotlessLDir objectAtIndex: row ];
    } else {
        dict = [ localDirContents objectAtIndex: row ];
    }
    type = [ dict objectForKey: @"type" ];
    path = [ dict objectForKey: @"name" ];
                
    if ( [ type isEqualToString: @"directory" ] ) {
        [ self localBrowserReloadForPath: path ];
    } else if ( [ type isEqualToString: @"alias" ] ||
                [ type isEqualToString: @"symbolic link" ] ) {
        /* resolve alias or link, determine if directory */
        NSString	*resolvedpath = [ dict objectForKey: @"resolvedAlias" ];
        struct stat	st;
        
        if ( resolvedpath == nil ) {
            NSBeep();
            return;
        }
        
        if ( stat(( char * )[ resolvedpath UTF8String ], &st ) < 0 ) {
            NSLog( @"stat %@: %s", resolvedpath, strerror( errno ));
            return;
        }
        
        if ( S_ISDIR( st.st_mode )) {
            [ self localBrowserReloadForPath: resolvedpath ];
        }
    }
}

- ( IBAction )uploadButtonClick: ( id )sender
{
    NSEnumerator	*en = [ localBrowser selectedRowEnumerator ];
    NSMutableArray	*marray = [[ NSMutableArray alloc ] init ];
    NSDictionary	*dict = nil;
    id			nobj;
    
    while (( nobj = [ en nextObject ] ) != nil ) {
        dict = [ ( dotflag ? localDirContents : dotlessLDir )
                                objectAtIndex: [ nobj intValue ]];
                                
        [ marray addObject: [ dict objectForKey: @"name" ]];
    }
    [ self uploadFiles: marray toDirectory: @"." ];
    [ marray release ];
}

- ( IBAction )remoteBrowserSingleClick: ( id )browser
{
    if ( [ infoPanel isVisible ] ) [ self getInfo: nil ];
}

- ( IBAction )downloadButtonClick: ( id )sender
{
    NSEnumerator	*en = [ remoteBrowser selectedRowEnumerator ];
    NSMutableArray	*marray = [[ NSMutableArray alloc ] init ];
    NSAutoreleasePool	*p = [[ NSAutoreleasePool alloc ] init ];
    NSDictionary	*d;
    id			nobj;
    
    while (( nobj = [ en nextObject ] ) != nil ) {
        d = [ ( dotflag ? remoteDirContents : dotlessRDir ) objectAtIndex: [ nobj intValue ]];
        
        if ( [[ d objectForKey: @"type" ] isEqualToString: @"directory" ] ) {
            int			rc;

            rc = NSRunAlertPanel( NSLocalizedString( @"Warning: OpenSSH's sftp client "
                                                    @"cannot yet download directories.",
                                                    @"Warning: OpenSSH's sftp client "
                                                    @"cannot yet download directories." ),
                NSLocalizedString( @"Would you like to download %@ to %@ with SCP instead?",
                                @"Would you like to download %@ to %@ with SCP instead?" ),
                NSLocalizedString( @"Download", @"Download" ),
                NSLocalizedString( @"Cancel", @"Cancel" ), @"",
                [ d objectForKey: @"name" ], localDirPath );
            switch ( rc ) {
            case NSAlertDefaultReturn:
                [ self scpRemoteItem: [ d objectForKey: @"name" ]
                        fromHost: [ remoteHost stringValue ]
                        toLocalPath: localDirPath userName: [ userName stringValue ]];
            case NSAlertAlternateReturn:
            default:
                continue;
            }
        }
        [ marray addObject: d ];
    }
    [ p release ];
    [ self downloadFiles: marray toDirectory: localDirPath ];
    [ marray release ];
}

- ( IBAction )remoteBrowserDoubleClick: ( id )browser
{
    int			rcrow = [ remoteBrowser clickedRow ];
    NSDictionary	*remoteItem;
    int			type;
    
    /* double-click in the header cell */
    if ( rcrow < 0 ) {
        if (( rcrow = [ remoteBrowser selectedRow ] ) < 0 ) {
            return;
        }
    }
    
    if ( !dotflag ) {
        remoteItem = [ dotlessRDir objectAtIndex: rcrow ];
    } else {
        remoteItem = [ remoteDirContents objectAtIndex: rcrow ];
    }
    
    type = [[ remoteItem objectForKey: @"perm" ] characterAtIndex: 0 ];
    
    if ( rcrow >= 0 && ( type == 'd' || type == 'l' )) {
        NSData          *nameData = [ remoteItem objectForKey: @"NameAsRawBytes" ];
        char            name[ MAXPATHLEN ] = { 0 };
        char            cmdline[ LINE_MAX ];

        memcpy( name, [ nameData bytes ], [ nameData length ] );
        if ( snprintf( cmdline, LINE_MAX, "cd \"%s\"", name )
                    >= LINE_MAX ) {
            NSLog( @"cd \"%s\": too long", name );
            return;
        }
        [ self writeCommand: cmdline ];
        
        /* wait till we're at the prompt before continuing */
        while ( ![ tServer atSftpPrompt ] ) ;
        [ self getListing ];
    } else {
        [ self downloadFiles: [ NSArray arrayWithObject: remoteItem ]
            toDirectory: localDirPath ];
    }
}

- ( IBAction )showLocalHistoryMenu: ( id )sender
{
    NSEvent		*e = [ NSApp currentEvent ];
    
    if ( ! [ sender isKindOfClass: [ NSToolbarItem class ]] ) {
	return;
    }
			    
    [ NSMenu popUpContextMenu: localHistoryMenu withEvent: e forView: [ sender view ]];
}

- ( IBAction )showRemoteHistoryMenu: ( id )sender
{
    NSEvent		*e = [ NSApp currentEvent ];
                                    
    [ NSMenu popUpContextMenu: remoteHistoryMenu withEvent: e forView: nil ];
}

- ( NSMutableArray * )uploadQ
{
    return( uploadQueue );
}

- ( NSMutableArray * )downloadQ
{
    return( downloadQueue );
}

- ( void )uploadFiles: ( NSArray * )lfiles toDirectory: ( NSString * )rpath
{
    BOOL                noSafetyNet = NO;
    struct stat         st;
    int			i, j, rc, skip = 0, clobber = 0;
    
    if ( ! connected ) return;

    noSafetyNet = [[ NSUserDefaults standardUserDefaults ]
                        boolForKey: @"TrapezeWithNoNet" ];
                        
    for ( i = 0; i < [ lfiles count ]; i++ ) {
        if ( !noSafetyNet && !clobber ) {
            for ( j = 0; j < [ remoteDirContents count ]; j++ ) {
                if ( [ rpath isEqualToString: @"." ] &&
                        [[[ remoteDirContents objectAtIndex: j ] objectForKey: @"name" ]
                            isEqualToString: [[ lfiles objectAtIndex: i ] lastPathComponent ]] ) {
                    rc = NSRunAlertPanel( [ NSString stringWithFormat:
                            NSLocalizedString( @"%@ exists. Overwrite?",
                                            @"%@ exists. Overwrite?" ),
                                                [[ lfiles objectAtIndex: i ] lastPathComponent ]],
                            @"", NSLocalizedString( @"Cancel", @"Cancel" ),
                                    NSLocalizedString( @"Overwrite", @"Overwrite" ),
                                    NSLocalizedString( @"Overwrite All", @"Overwrite All" ));
                    switch ( rc ) {
                    default:
                    case NSAlertDefaultReturn:
                        skip++;
                        return;
                    case NSAlertAlternateReturn:
                        break;
                    case NSAlertOtherReturn:
                        clobber++;
                        break;
                    }
                }
            }
        }
        if ( !skip || clobber ) {
            if ( stat(( void * )[[ lfiles objectAtIndex: i ] UTF8String ], &st ) < 0 ) {
                NSLog( @"stat %@: %s", [ lfiles objectAtIndex: i ], strerror( errno ));
                continue;
            }
            
            basedir = [ NSString stringWithFormat: @"%@/%@", rpath,
                                [[ lfiles objectAtIndex: i ] lastPathComponent ]];
            
            if ( st.st_mode & S_IFDIR ) {
                [ self prepareDirUpload: [ lfiles objectAtIndex: i ]];
            } else {
                [ uploadQueue addObject: [ NSDictionary dictionaryWithObjectsAndKeys:
                                                [ NSNumber numberWithInt: 0 ], @"isdir",
                                                [ lfiles objectAtIndex: i ], @"fullpath",
                                                basedir, @"pathfrombase", nil ]];
            }
        }
        skip = 0;
    }

    [ self writeCommand: " " ];
}

- ( void )downloadFiles: ( NSArray * )rpaths toDirectory: ( NSString * )lpath
{
    int		i, j, rc, skip = 0, clobber = 0;
    NSArray	*lpathContents = nil;
    NSData      *rawdata = nil;
    BOOL        noSafetyNet = NO;
    
    if ( ! connected ) return;
    
    lpathContents = [[ NSFileManager defaultManager ] directoryContentsAtPath: lpath ];
    
    noSafetyNet = [[ NSUserDefaults standardUserDefaults ]
                        boolForKey: @"TrapezeWithNoNet" ];
    
    for ( i = 0; i < [ rpaths count ]; i++ ) {
        if ( !noSafetyNet && !clobber ) {
            for ( j = 0; j < [ lpathContents count ]; j++ ) {
                if ( [[ lpathContents objectAtIndex: j ] isEqualToString:
                            [[ rpaths objectAtIndex: i ] objectForKey: @"name" ]] && !clobber ) {
                    rc = NSRunAlertPanel( [ NSString stringWithFormat:
                            NSLocalizedString( @"%@ exists. Overwrite?",
                                                @"%@ exists. Overwrite?" ),
                                [[ rpaths objectAtIndex: i ] objectForKey: @"name" ]],
                            @"", NSLocalizedString( @"Cancel", @"Cancel" ),
                                NSLocalizedString( @"Overwrite", @"Overwrite" ),
                                NSLocalizedString( @"Overwrite All", @"Overwrite All" ));
                    switch ( rc ) {
                    case NSAlertDefaultReturn:
                        skip = 1;
                        break;
                        
                    case NSAlertAlternateReturn:
                        break;
                        
                    case NSAlertOtherReturn:
                        clobber = 1;
                        break;
                    }
                    break;
                }
            }
        }
        if ( !skip || clobber ) {
            rawdata = [[ rpaths objectAtIndex: i ] objectForKey: @"NameAsRawBytes" ];
            [ downloadQueue addObject:
                        [ NSDictionary dictionaryWithObjectsAndKeys:
                            rawdata, @"rpath",
                            lpath, @"lpath", nil ]];
        }
        skip = 0;
    }
    
    [ self writeCommand: " " ];
}

- ( void )showDownloadProgressWithMessage: ( char * )msg
{
    NSString		*mesg = [ NSString stringWithFormat:
                            NSLocalizedString( @"Downloading %s...",
                                @"Downloading %s..." ), msg ];
    
    [ downloadTextField setStringValue: mesg ];
    [ downloadProgBar setAnimationDelay: ( 20.0 / 60.0 ) ];
    [ downloadProgBar setUsesThreadedAnimation: YES ];
    [ downloadProgBar startAnimation: nil ];
    
    if ( timer == nil ) {
        [ downloadTimeField setStringValue: @"00:00:00" ];
        dltime = 0;
        timer = [ NSTimer scheduledTimerWithTimeInterval: 5.0 target: self
                            selector: @selector( dlUpdate ) userInfo: nil
                            repeats: YES ];
    }
    
    if ( ![ downloadSheet isVisible ] ) {
        [ NSApp beginSheet: downloadSheet
                modalForWindow: mainWindow
                modalDelegate: self
                didEndSelector: NULL
                contextInfo: nil ];
    }
}

- ( void )updateDownloadProgressBarWithValue: ( double )value
	    amountTransfered: ( NSString * )amount
	    transferRate: ( NSString * )rate
	    ETA: ( NSString * )eta
{
    double		pc_done = value;

    [ downloadProgBar stopAnimation: nil ];
    [ downloadProgBar setIndeterminate: NO ];
    [ downloadProgBar setMinValue: 0.0 ];
    [ downloadProgBar setMaxValue: 100.0 ];
    [ downloadProgBar setDoubleValue: pc_done ];
    [ downloadProgInfo setStringValue: [ NSString stringWithFormat: @"%@\n%@\n%@", amount, rate, eta ]];
    [ downloadProgPercentDone setStringValue: [ NSString stringWithFormat: @"%d%%", ( int )value ]];
}

- ( void )dlUpdate
{
    dltime += 5.0;
    [ downloadTimeField setStringValue: [ NSString clockStringFromInteger: dltime ]];
}

- ( void )finishedDownload
{
    [ downloadSheet orderOut: nil ];
    [ NSApp endSheet: downloadSheet ];
    [ downloadProgBar setIndeterminate: YES ];
    [ downloadProgBar stopAnimation: nil ];
    
    if ( [[ self editedDocuments ] count ] > 0 ) {
	NSDictionary	*dict = [[ self editedDocuments ] lastObject ];
	
	[ self ODBEditFile: [ dict objectForKey: @"localpath" ]
		remotePath: [ dict objectForKey: @"remotepath" ]];
    }
    
    if ( [ self previewedImage ] != nil ) {
        [ self displayPreview ];
    }
    
    [ timer invalidate ];
    timer = nil;
    
    [[ NSWorkspace sharedWorkspace ] noteFileSystemChanged ];
    [ self localBrowserReloadForPath: localDirPath ];
}

- ( void )delete: ( id )sender
{
    if ( [ sender isEqual: localBrowser ]
                || [[ mainWindow firstResponder ] isEqual: localBrowser ] ) {
        [ self deleteLocalFile: nil ];
    } else if ( [ sender isEqual: remoteBrowser ]
                || [[ mainWindow firstResponder ] isEqual: remoteBrowser ] ) {
        [ self deleteRemoteFile: nil ];
    }
}

- ( IBAction )deleteLocalFile: ( id )sender
{
    int				i = 0, rc, optag, row = [ localBrowser selectedRow ];
    unsigned long int		numberoflines = [ localBrowser numberOfSelectedRows ];
    unsigned long int		selectedlines[ numberoflines ];
    NSMutableArray		*items, *source;
    NSString			*fn;
    NSEnumerator		*en;
    id				tobj, contents;
    NSAutoreleasePool		*p;
    
    if ( row < 0 ) {
        return;
    }
    
    source = ( dotflag ? localDirContents : dotlessLDir );
    items = [[ NSMutableArray alloc ] init ];
    en = [ localBrowser selectedRowEnumerator ];
    p = [[ NSAutoreleasePool alloc ] init ];
    
    while (( tobj = [ en nextObject ] ) != nil ) {
        [ items addObject: [[[ source objectAtIndex:
                [ tobj intValue ]] objectForKey: @"name" ] lastPathComponent ]];
        selectedlines[ i ] = [ tobj intValue ];
        i++;
    }
    [ p release ];

    switch ( [ items count ] ) {
    case 0:
        [ items release ];
        return;
    case 1:
        fn = [ items objectAtIndex: 0 ];
        break;
    default:
        fn = NSLocalizedString( @"the selected items", @"the selected items" );
        break;
    }
    [[ NSUserDefaults standardUserDefaults ] setBool: YES forKey: @"confirmdelete" ];
    [[ NSUserDefaults standardUserDefaults ] synchronize ];
    rc = NSRunAlertPanel( [ NSString stringWithFormat:
                NSLocalizedString( @"Do you want to move %@ to the Trash?",
                        @"Do you want to move %@ to the Trash?" ), fn ],
            NSLocalizedString( @"You cannot undo this action.",
                        @"You cannot undo this action." ),
            NSLocalizedString( @"Delete", @"Delete" ),
            NSLocalizedString( @"Cancel", @"Cancel" ), @"" );
            
    switch ( rc ) {
    default:
    case NSAlertDefaultReturn:
        break;
    case NSAlertAlternateReturn:
        return;
    }

    contents = ( dotflag ? localDirContents : dotlessLDir );
    [ contents removeObjectsFromIndices: ( unsigned * )selectedlines
                numIndices: numberoflines ];
    [ localBrowser reloadData ];
    
    if ( [[ NSWorkspace sharedWorkspace ] performFileOperation: NSWorkspaceRecycleOperation
					source: localDirPath destination: @"/"
					files: items tag: &optag ] == NO ) {
	NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
                NSLocalizedString( @"Couldn't delete %@.", @"Couldn't delete %@." ),
		NSLocalizedString( @"OK", @"OK" ), @"", @"", fn );
	return;
    }

    [[ NSWorkspace sharedWorkspace ] noteFileSystemChanged: localDirPath ];

    [ self localBrowserReloadForPath: localDirPath ];
    [ localBrowser reloadData ];
}

- ( IBAction )deleteRemoteFile: ( id )sender
{
    int				rc, i, row = [ remoteBrowser selectedRow ];
    NSMutableDictionary		*dict;
    NSEnumerator		*en;
    NSMutableArray		*items;
    NSAutoreleasePool		*p;
    id				dobj;
    NSString			*fn, *item, *deleteCommand = nil;
    char			*delcmd = NULL;
    
    if ( row < 0 || !connected ) return;
    
    items = [[ NSMutableArray alloc ] init ];
    en = [ remoteBrowser selectedRowEnumerator ];
    p = [[ NSAutoreleasePool alloc ] init ];
    
    while (( dobj = [ en nextObject ] ) != nil ) {
        [ items addObject: (( dotflag ) ?
                [ remoteDirContents objectAtIndex: [ dobj intValue ]] :
                [ dotlessRDir objectAtIndex: [ dobj intValue ]] ) ];
    }
    [ p release ];

    switch ( [ items count ] ) {
    case 0:
        [ items release ];
        return;
    case 1:
        fn = [[ items objectAtIndex: 0 ] objectForKey: @"name" ];
        break;
    default:
        fn = NSLocalizedString( @"the selected items", @"the selected items" );
        break;
    }
    
    rc = NSRunAlertPanel( [ NSString stringWithFormat:
            NSLocalizedString( @"Delete %@?", @"Delete %@?" ), fn ],
            NSLocalizedString( @"%@ will be deleted immediately. "
                                @"You will not be able to undo this action.",
                                @"%@ will be deleted immediately. "
                                @"You will not be able to undo this action." ),
            NSLocalizedString( @"Delete", @"Delete" ),
            NSLocalizedString( @"Cancel", @"Cancel" ), @"", fn );
            
    switch ( rc ) {
    default:
    case NSAlertDefaultReturn:
        break;
    case NSAlertAlternateReturn:
        return;
    }
    
    if ( removeQueue == nil ) removeQueue = [[ NSMutableArray alloc ] init ];
    p = [[ NSAutoreleasePool alloc ] init ];
    for ( i = 0; i < [ items count ]; i++ ) {
        dict = [ items objectAtIndex: i ];
        
        if ( [[ dict objectForKey: @"perm" ] characterAtIndex: 0 ] == 'd' ) {
            delcmd = "rmdir";
        } else {
            delcmd = "rm";
        }
        item = nil;
        item = [ dict objectForKey: @"name" ];

        deleteCommand = [ NSString stringWithFormat: @"%s \"%@\"", delcmd, item ];
        [ removeQueue addObject: deleteCommand ];
    }
    [ p release ];
    [ self writeCommand: " " ];
    [ remoteProgBar setIndeterminate: NO ];
    [ remoteProgBar setMinValue: 0.0 ];
    [ remoteProgBar setMaxValue: [ removeQueue count ]];
    [ remoteProgBar setDoubleValue: 0.0 ];
}

- ( void )deleteFirstItemFromRemoveQueue
{
    int		count = [ removeQueue count ];
    
    if ( ! count ) return;

    [ self writeCommand: ( char * )[[ removeQueue objectAtIndex: 0 ] UTF8String ]];
    [ removeQueue removeObjectAtIndex: 0 ];
    switch ( count ) {
    case 0:
        [ removeQueue release ];
        removeQueue = nil;
        break;
    case 1:
        [ remoteProgBar setIndeterminate: YES ];
        [ remoteProgBar startAnimation: nil ];
        break;
    default:
        [ remoteProgBar incrementBy: 1.0 ];
        break;
    }
}

- ( NSMutableArray * )removeQ
{
    return( removeQueue );
}

- ( IBAction )toggleDirCreationButtons: ( id )sender
{
    [ localDirCreateButton setState: NSOffState ];
    [ remoteDirCreateButton setState: NSOffState ];
    [ sender setState: NSOnState ];
    if ( [[ sender title ] isEqualToString:
            NSLocalizedString( @"Locally", @"Locally" ) ] ) {
        [ newDirCreateButton setAction: @selector( makeLDir ) ];
    } else {
        [ newDirCreateButton setAction: @selector( makeRDir ) ];
    }
}

- ( IBAction )createNewDirectory: ( id )sender
{
    id			activeTableView = nil;
    
    if ( [ mainWindow isKeyWindow ] ) {
        activeTableView = [ mainWindow firstResponder ];
        
        if ( [ activeTableView isEqual: localBrowser ] || ! connected ) {
            [ localDirCreateButton setState: NSOnState ];
            [ remoteDirCreateButton setState: NSOffState ];
        } else {
            [ remoteDirCreateButton setState: NSOnState ];
            [ localDirCreateButton setState: NSOffState ];
        }
    }
    
    if ( [ localDirCreateButton state ] ) {
        [ newDirCreateButton setAction: @selector( makeLDir ) ];
    } else if ( [ remoteDirCreateButton state ] ) {
        [ newDirCreateButton setAction: @selector( makeRDir ) ];
    }
    [ NSApp beginSheet: newDirPanel
            modalForWindow: mainWindow
            modalDelegate: self
            didEndSelector: NULL
            contextInfo: nil ];
}

- ( void )makeRDir
{
    if ( !connected ) return;
    
    [ self writeCommand: ( char * )[[ NSString
            stringWithFormat: @"mkdir \"%@\"",
            [ newDirNameField stringValue ]] UTF8String ]];
            
    while ( ![ tServer atSftpPrompt ] ) ;
    [ self getListing ];
    
    [ self dismissNewDirPanel: nil ];
}

- ( void )makeLDir
{
    NSString		*lpath = [ NSString stringWithFormat:
                                    @"%@/%@",
                                    localDirPath,
                                    [ newDirNameField stringValue ]];
                                    
    if ( mkdir(( char * )[ lpath UTF8String ], 0755 ) != 0 ) {
        NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
            NSLocalizedString( @"Couldn't create %@: %s", @"Couldn't create %@: %s" ),
            @"OK", @"", @"", lpath, strerror( errno ));
    }
    
    [ self localBrowserReloadForPath: localDirPath ];
    [[ NSWorkspace sharedWorkspace ] noteFileSystemChanged: localDirPath ];
    
    [ self dismissNewDirPanel: nil ];
}

- ( IBAction )dismissNewDirPanel: ( id )sender
{
    [ newDirPanel orderOut: nil ];
    [ NSApp endSheet: newDirPanel ];
}

- ( IBAction )changeROwner: ( id )sender
{
    char	cmd[ MAXPATHLEN ];
    int		i;
    
    if ( ![[ rOwnerField stringValue ] length ] ) {
        goto CHOWN_ERROR;
    }
    for ( i = 0; i < [[ rOwnerField stringValue ] length ]; i++ ) {
        if ( !isdigit( [[ rOwnerField stringValue ] characterAtIndex: i ] )) {
            goto CHOWN_ERROR;
        }
    }
    
    if ( snprintf( cmd, MAXPATHLEN, "chown %s \"%s\"",
                ( char * )[[ rOwnerField stringValue ] UTF8String ],
                ( char * )[[ rWhereField stringValue ] UTF8String ] )
            > ( MAXPATHLEN - 1 )) {
        NSLog( @"Buffer overflow." );
        return;
    }
    
    [ self writeCommand: cmd ];
    return;

CHOWN_ERROR:
    NSBeginAlertSheet( NSLocalizedStringFromTable( @"Invalid owner user identification number.",
                        @"SFTPInfoPanel",
                        @"Invalid owner user identification number." ),
                          @"OK", @"", @"", infoPanel,
                          self, NULL, nil, NULL,
                        NSLocalizedStringFromTable(
                            @"You must provide a numeric uid for this action.", @"SFTPInfoPanel",
                            @"You must provide a numeric uid for this action." ));
}

- ( IBAction )changeRGroup: ( id )sender
{
    char	cmd[ MAXPATHLEN ];
    int		i;
    
    if ( ![[ rGroupField stringValue ] length ] ) {
        goto CHGRP_ERROR;
    }
    for ( i = 0; i < [[ rGroupField stringValue ] length ]; i++ ) {
        if ( !isdigit( [[ rGroupField stringValue ] characterAtIndex: i ] )) {
            goto CHGRP_ERROR;
        }
    }
    
    if ( snprintf( cmd, MAXPATHLEN, "chgrp %s \"%s\"",
                ( char * )[[ rGroupField stringValue ] UTF8String ],
                ( char * )[[ rWhereField stringValue ] UTF8String ] )
            > ( MAXPATHLEN - 1 )) {
        NSLog( @"Buffer overflow." );
        return;
    }
    
    [ self writeCommand: cmd ];
    return;

CHGRP_ERROR:
    NSBeginAlertSheet( NSLocalizedStringFromTable( @"Invalid group identification number.",
                        @"SFTPInfoPanel",
                        @"Invalid group identification number." ),
                          @"OK", @"", @"", infoPanel,
                          self, NULL, nil, NULL,
                        NSLocalizedStringFromTable(
                            @"You must provide a numeric gid for this operation.",
                            @"SFTPInfoPanel",
                            @"You must provide a numeric gid for this operation." ));
}

- ( IBAction )remotePermissionSwitchClick: ( id )sender
{
    int			own = 0, grp = 0, oth = 0;
    char		bit;
    
    if ( [[ rSwitchArray objectAtIndex: 0 ] state ] == NSOnState ) own += 4;
    if ( [[ rSwitchArray objectAtIndex: 1 ] state ] == NSOnState ) own += 2;
    if ( [[ rSwitchArray objectAtIndex: 2 ] state ] == NSOnState ) own += 1;
    if ( [[ rSwitchArray objectAtIndex: 3 ] state ] == NSOnState ) grp += 4;
    if ( [[ rSwitchArray objectAtIndex: 4 ] state ] == NSOnState ) grp += 2;
    if ( [[ rSwitchArray objectAtIndex: 5 ] state ] == NSOnState ) grp += 1;
    if ( [[ rSwitchArray objectAtIndex: 6 ] state ] == NSOnState ) oth += 4;
    if ( [[ rSwitchArray objectAtIndex: 7 ] state ] == NSOnState ) oth += 2;
    if ( [[ rSwitchArray objectAtIndex: 8 ] state ] == NSOnState ) oth += 1;
    
    if ( ![[ rPermField stringValue ] length ] ) bit = '0';
    else bit = [[ rPermField stringValue ] characterAtIndex: 0 ];
    
    if ( !isdigit( bit )) bit = '0';
    
    [ rPermField setStringValue: [ NSString stringWithFormat: @"%c%d%d%d",
            bit, own, grp, oth ]];
}

- ( IBAction )changeRemoteMode: ( id )sender
{
    int			i;
    char		cmd[ MAXPATHLEN ];
    
    if ( [[ rPermField stringValue ] length ] != 4 ) goto CHMOD_ERROR; 
    for ( i = 0; i < [[ rPermField stringValue ] length ]; i++ ) {
        if ( !isdigit( [[ rPermField stringValue ] characterAtIndex: i ] )) {
            goto CHMOD_ERROR;
        }
    }
    
    if ( snprintf( cmd, MAXPATHLEN, "chmod %s \"%s\"",
                        ( char * )[[ rPermField stringValue ] UTF8String ],
                        ( char * )[[ rWhereField stringValue ] UTF8String ] )
                > ( MAXPATHLEN - 1 )) {
        NSLog( @"buffer overflow" );
        return;
    }
    
    [ self writeCommand: cmd ];
    return;
    
CHMOD_ERROR:
    NSBeginAlertSheet( NSLocalizedStringFromTable( @"Invalid octal permissions set.",
                        @"SFTPInfoPanel", @"Invalid octal permissions set." ),
                          @"OK", @"", @"", infoPanel,
                          self, NULL, nil, NULL,
                        NSLocalizedStringFromTable(
                        @"You must provide a four-digit octal permissions set for this operation.",
                            @"SFTPInfoPanel",
                        @"You must provide a four-digit octal permissions set for this operation." ));
}

- ( IBAction )changeLOwnerAndGroup: ( id )sender
{
    uid_t	u;
    gid_t	g;
    
    if ( ![[ ownerField stringValue ] length ] ) return;
    if ( ![[ groupField stringValue ] length ] ) return;
    
    g = ( gid_t )[ groupField intValue ];
    u = ( uid_t )[ ownerField intValue ];
    
    /* only root can change owners */
    if ( getuid() != 0 && u != getuid()) u = getuid();
    
    if ( chown(( char * )[[ whereField stringValue ] UTF8String ], u, g ) < 0 ) {
        NSBeginAlertSheet( NSLocalizedStringFromTable( @"Error changing owner.", @"SFTPInfoPanel",
                            @"Error changing owner." ),
                          @"OK", @"", @"", infoPanel,
                          self, NULL, nil, NULL,
                          @"chown %@: %s", [ whereField stringValue ],
                            strerror( errno ));
        return;
    }
}

- ( IBAction )changeLocalMode: ( id )sender
{
    mode_t	mode;
    
    if ( ![[ permField stringValue ] length ] ) return;
    
    mode = ( mode_t )( strtol(( char * )[[ permField stringValue ] UTF8String ], NULL, 8 ));
    if ( errno == ERANGE || errno == EINVAL ) {
        NSLog( @"strtol failed: %s", strerror( errno ));
        return;
    }
    if ( chmod(( char * )[[ whereField stringValue ] UTF8String ], mode ) < 0 ) {
        NSBeginAlertSheet( NSLocalizedStringFromTable( @"Error changing permissions.",
                            @"SFTPInfoPanel", @"Error changing permissions." ),
                          @"OK", @"", @"", infoPanel,
                          self, NULL, nil, NULL,
                          @"chmod %@: %s", [ infoPathField stringValue ],
                            strerror( errno ));
        return;
    }
    [ self localBrowserReloadForPath: localDirPath ];
}

- ( IBAction )localPermissionSwitchClick: ( id )sender
{
    int			own = 0, grp = 0, oth = 0;
    char		bit;
    
    if ( [ loReadSwitch state ] == NSOnState ) own += 4;
    if ( [ loWriteSwitch state ] == NSOnState ) own += 2;
    if ( [ loExecSwitch state ] == NSOnState ) own += 1;

    if ( [ lgReadSwitch state ] == NSOnState ) grp += 4;
    if ( [ lgWriteSwitch state ] == NSOnState ) grp += 2;
    if ( [ lgExecSwitch state ] == NSOnState ) grp += 1;

    if ( [ laReadSwitch state ] == NSOnState ) oth += 4;
    if ( [ laWriteSwitch state ] == NSOnState ) oth += 2;
    if ( [ laExecSwitch state ] == NSOnState ) oth += 1;
    
    if ( ![[ permField stringValue ] length ] ) bit = '0';
    else bit = [[ permField stringValue ] characterAtIndex: 0 ];
    
    if ( !isdigit( bit )) bit = '0';
    
    [ permField setStringValue: [ NSString stringWithFormat: @"%c%d%d%d",
            bit, own, grp, oth ]];
}

- ( IBAction )toggleGoToButtons: ( id )sender
{
    [ localGotoButton setState: NSOffState ];
    [ remoteGotoButton setState: NSOffState ];
    [ sender setState: NSOnState ];
    if ( [[ sender title ] isEqualToString:
            NSLocalizedString( @"Locally",
                    @"Locally" ) ] ) {
        [ gotoButton setAction: @selector( gotoLocalDirectory: ) ];
    } else {
        [ gotoButton setAction: @selector( gotoRemoteDirectory: ) ];
    }
}

- ( IBAction )getGotoDirPanel: ( id )sender
{
    id			activeTableView = nil;
    
    if ( [ mainWindow isKeyWindow ] ) {
        activeTableView = [ mainWindow firstResponder ];
        
        if ( [ activeTableView isEqual: localBrowser ] || ! connected ) {
            [ remoteGotoButton setState: NSOffState ];
            [ localGotoButton setState: NSOnState ];
        } else {
            [ remoteGotoButton setState: NSOnState ];
            [ localGotoButton setState: NSOffState ];
        }
    }
    
    if ( [ localGotoButton state ] ) {
        [ gotoButton setAction: @selector( gotoLocalDirectory: ) ];
    } else if ( [ remoteGotoButton state ] ) {
        [ gotoButton setAction: @selector( gotoRemoteDirectory: ) ];
    }

    [ gotoDirNameField setCompletes: YES ];
    [ NSApp beginSheet: gotoDirPanel
            modalForWindow: mainWindow
            modalDelegate: self
            didEndSelector: NULL
            contextInfo: nil ];
}

- ( IBAction )gotoLocalDirectory: ( id )sender
{
    [ self localBrowserReloadForPath:
            [[ gotoDirNameField stringValue ] stringByExpandingTildeInPath ]];
    [ self dismissGotoDirPanel: nil ];
}

- ( IBAction )gotoRemoteDirectory: ( id )sender
{
    NSString		*dircmd, *newpath = [ gotoDirNameField stringValue ];
    
    /*
     * try to handle a ~ in a remote dir path.
     * this will fail if some home dirs are
     * not in the same location as the logged in user's.
     * will also fail if user specified a dir
     * in the connect pane.
     */
    newpath = [ newpath stringByExpandingTildeInRemotePathWithHomeSetAs: remoteHome ];
    
    dircmd = [ NSString stringWithFormat: @"cd \"%@\"", newpath ];
    
    if ( ! connected ) return;
    
    [ self writeCommand: ( char * )[ dircmd UTF8String ]];
    [ self dismissGotoDirPanel: nil ];
    while( ![ tServer atSftpPrompt ] ) ;
    [ self getListing ];
    [ gotoDirNameField insertItemWithObjectValue: [ gotoDirNameField stringValue ] atIndex: 0 ];
}

- ( IBAction )dismissGotoDirPanel: ( id )sender
{
    [ gotoDirPanel orderOut: nil ];
    [ NSApp endSheet: gotoDirPanel ];
}

- ( IBAction )cdRemoteHome: ( id )sender
{
    if ( !connected ) return;
    
    [ self writeCommand:
                ( char * )[[ NSString stringWithFormat: @"cd %@", remoteHome ] UTF8String ]];
                
    while ( ![ tServer atSftpPrompt ] ) ;
    [ self getListing ];
}

- ( IBAction )cdLocalHome: ( id )sender
{
    NSString		*hdir = [[ NSUserDefaults standardUserDefaults ]
                                    objectForKey: @"defaultdir" ];
                                    
    if ( hdir == nil || ! [ hdir length ] ) hdir = NSHomeDirectory();
    [ self localBrowserReloadForPath: hdir ];
}

- ( IBAction )remoteCdDotDot: ( id )sender
{
    if ( !connected ) return;
    
    [ self writeCommand: "cd .." ];
                
    /* wait till we're at the prompt before continuing */
    while ( ![ tServer atSftpPrompt ] ) ;
    [ self getListing ];
}

- ( IBAction )localCdDotDot: ( id )sender
{
    NSString			*item;
    
    item = [ localDirPath stringByDeletingLastPathComponent ];
    if ( item == nil || ![ item length ] ) return;
    [ self localBrowserReloadForPath: item ];
}

- ( IBAction )cdFromRemoteHistoryMenu: ( id )sender
{
    NSString		*dircmd;
    
    dircmd = [ NSString stringWithFormat: @"cd \"%@\"", [ sender title ]];
    [ self writeCommand: ( char * )[ dircmd UTF8String ]];
    while( ![ tServer atSftpPrompt ] ) ;
    [ self getListing ];
}

- ( IBAction )cdFromLocalHistoryMenu: ( id )sender
{
    [ self localBrowserReloadForPath: [ sender title ]];
}

- ( IBAction )cdFromLPathPopUp: ( id )sender
{
    NSString	*path, *component;
    int		index, i = 0;
    
    path = [ NSString stringWithString: localDirPath ];
    component = [ lPathPopUp titleOfSelectedItem ];
    index = [ lPathPopUp indexOfSelectedItem ];
    
    if ( [ component isEqualToString: @"/" ] ) {
        [ self localBrowserReloadForPath: @"/" ];
        return;
    }
    
    if ( ! [ path containsString: component ] ) {
        NSLog( @"Screwed up local popup list." );
        [ self localBrowserReloadForPath: path ];
        return;
    }
    for ( i = 0; i != index; i++ ) {
        path = [ path stringByDeletingLastPathComponent ];
    }
    if ( ! [[ path lastPathComponent ] isEqualToString: component ] ) {
        NSLog( @"Failed to find %@ in %@", component, localDirPath );
        return;
    }
    
    [ self localBrowserReloadForPath: path ];
}

- ( IBAction )cdFromRPathPopUp: ( id )sender
{
    NSString	*path, *component, *dircmd;
    int		index, i;
    
    if ( ! connected ) return;
    
    path = [ NSString stringWithString: remoteDirPath ];
    component = [ rPathPopUp titleOfSelectedItem ];
    index = [ rPathPopUp indexOfSelectedItem ];
    
    if ( [ component isEqualToString: @"/" ] ) {
        [ self writeCommand: "cd /" ];
        while( ! [ tServer atSftpPrompt ] ) ;
        [ self getListing ];
        return;
    }
    
    if ( ! [ path containsString: component ] ) {
        NSLog( @"Screwed up remote popup list. Correcting." );
        [ self writeCommand: "pwd" ];
        return;
    }
    
    for ( i = 0; i != index; i++ ) {
        path = [ path stringByDeletingLastPathComponent ];
    }
    if ( ! [[ path lastPathComponent ] isEqualToString: component ] ) {
        NSLog( @"Failed to find %@ in %@", component, remoteDirPath );
        return;
    }
    
    dircmd = [ NSString stringWithFormat: @"cd \"%@\"", path ];
    [ self writeCommand: ( char * )[ dircmd UTF8String ]];
    while( ![ tServer atSftpPrompt ] ) ;
    [ self getListing ];
}

- ( void )performSpringLoadedActionInTable: ( NSTableView * )table
{
    NSPoint         location = [ NSEvent mouseLocation ];
    int             row;
    NSString        *path = nil;
    NSMutableArray  *contents;
    
    location = [[ table window ] convertScreenToBase: location ];
    location = [ table convertPoint: location
                        fromView: [[ table window ] contentView ]];
                    
    if (( row = [ table rowAtPoint: location ] ) < 0 ) {
        NSBeep();
        return;
    }
    
    if ( [ self springLoadedRootPath ] == nil ) {
        [ self setSpringLoadedRootPathInTable: table ];
    }
    
    if ( [ table isEqual: localBrowser ] ) {
        contents = ( dotflag ? localDirContents : dotlessLDir );
        path = [[ contents objectAtIndex: row ] objectForKey: @"name" ];
        
        if ( [[[ contents objectAtIndex: row ] objectForKey: @"type" ]
                isEqualToString: NSLocalizedString( @"directory", @"directory" ) ] ) {
            [ self localBrowserReloadForPath: path ];
        }
    } else if ( [ table isEqual: remoteBrowser ] ) {
        char        cmd[ MAXPATHLEN ];
        
        contents = ( dotflag ? remoteDirContents : dotlessRDir );
        path = [[ contents objectAtIndex: row ] objectForKey: @"name" ];
        
        if ( [[[ contents objectAtIndex: row ] objectForKey: @"type" ]
                isEqualToString: NSLocalizedString( @"directory", @"directory" ) ] ) {
            snprintf( cmd, MAXPATHLEN, "cd \"%s\"", [ path UTF8String ] );
            [ self writeCommand: cmd ];
            while ( ! [ tServer atSftpPrompt ] ) ;
            [ self getListing ];
        }
    }
}

- ( void )setSpringLoadedRootPathInTable: ( NSTableView * )table
{
    if ( _springLoadedRootPath != nil ) {
        [ _springLoadedRootPath release ];
        _springLoadedRootPath = nil;
    }
    
NSLog( @"setting springloaded root" );
    if ( [ table isEqual: remoteBrowser ] ) {
        _springLoadedRootPath = [ remoteDirPath copy ];
    } else if ( [ table isEqual: localBrowser ] ) {
        _springLoadedRootPath = [ localDirPath copy ];
    }
}

- ( NSString * )springLoadedRootPath
{
    return( _springLoadedRootPath );
}

- ( void )springLoadedActionCancelledInTable: ( SFTPTableView * )table
{
    NSString                *path = [ self springLoadedRootPath ];
    
    if ( path == nil ) {
        return;
    }
    
    if ( [ table isEqual: localBrowser ] ) {
        [ self localBrowserReloadForPath: path ];
    } else if ( [ table isEqual: remoteBrowser ] ) {
        [ self changeToRemoteDirectory: path ];
    }
    
    if ( _springLoadedRootPath != nil ) {
        [ _springLoadedRootPath release ];
        _springLoadedRootPath = nil;
    }
}

/* accessor methods for sftp command queue */
- ( void )queueSFTPCommand: ( const char * )fmt, ...
{
    NSData              *commandData = nil;
    NSMutableArray      *commandQueue = [ self SFTPCommandQueue ];
    va_list             val;
    char                cmd[ LINE_MAX ];
    
    va_start( val, fmt );
    if ( vsnprintf( cmd, LINE_MAX, fmt, val ) >= LINE_MAX ) {
        /* XXXX better error handling */
        NSLog( @"command too long" );
        return;
    }
    
    if ( commandQueue == nil ) {
        commandQueue = [[ NSMutableArray alloc ] init ];
    }
    commandData = [ NSData dataWithBytes: cmd length: strlen( cmd ) ];
    
    NSAssert(( commandData != nil ),
                @"+dataWithBytes:length: for command returned nil!" );
    
     /* emulate a FIFO. next command is retrieved with -lastObject */
    [ commandQueue insertObject: commandData atIndex: 0 ];
}

- ( NSMutableArray * )SFTPCommandQueue
{
    return( _sftpCommandQueue );
}

- ( id )nextSFTPCommandFromQueue
{
    id                  command = [[[ _sftpCommandQueue lastObject ] copy ] autorelease ];
    
    if ( [ _sftpCommandQueue count ] ) {
        [ _sftpCommandQueue removeLastObject ];
    }
    
    return( command );
}

- ( void )removeFirstItemFromUploadQ
{
    [ uploadQueue removeObjectAtIndex: 0 ];
}

- ( void )removeFirstItemFromDownloadQ
{
    [ downloadQueue removeObjectAtIndex: 0 ];
}

- ( void )prepareDirUpload: ( NSString * )directoryPath
{
    NSString		*pfb = nil;
    NSAutoreleasePool	*p = [[ NSAutoreleasePool alloc ] init ];
    FTS                 *tree = NULL;
    FTSENT              *item = NULL;
    char		dirpath[ MAXPATHLEN ];
    char                *ftspaths[ 2 ] = { NULL, NULL };
    int                 isdir = 0;
    
    if ( [ directoryPath length ] > sizeof( dirpath )) {
        NSLog( @"%@: too long\n" );
        return;
    }
    strcpy( dirpath, [ directoryPath UTF8String ] );
    
    ftspaths[ 0 ] = dirpath;
    
    if (( tree = fts_open( ftspaths, FTS_COMFOLLOW, 0 )) == NULL ) {
        NSLog( @"fts_open %s: %s", dirpath, strerror( errno ));
        return;
    }

    while (( item = fts_read( tree )) != NULL ) {
        isdir = 0;
        
        switch ( item->fts_info ) {
        case FTS_D:
            isdir = 1;
            break;
            
        case FTS_DP:
            continue;
        
        case FTS_ERR:
            NSLog( @"fts_read: %s", strerror( item->fts_errno ));
            continue;
        
        default:
            break;
        }

        pfb = [ NSString pathFromBaseDir: basedir
                fullPath: [ NSString stringWithUTF8String: item->fts_path ]];

        [ uploadQueue addObject:
                [ NSDictionary dictionaryWithObjectsAndKeys:
                [ NSNumber numberWithInt: isdir ], @"isdir",
                [ NSString stringWithUTF8String: item->fts_path ], @"fullpath",
                pfb, @"pathfrombase", nil ]];
    }
    if ( errno ) {
        NSLog( @"fts_read: %s", strerror( errno ));
    }
    
    if ( fts_close( tree ) != 0 ) {
        NSLog( @"fts_close: %s", strerror( errno ));
    }
    
    [ p release ];
}

- ( void )showUploadProgress
{
    if ( [ uploadProgPanel isVisible ] || [ mainWindow isMiniaturized ] ) {
	return;
    }
    
    [ uploadProgBar setMaxValue: ( double )[ uploadQueue count ]];
    [ uploadProgBar setUsesThreadedAnimation: YES ];
    [ uploadProgBar setIndeterminate: NO ];
    [ uploadTimeField setStringValue: @"00:00:00" ];
    
    ultime = 0;
    timer = [ NSTimer scheduledTimerWithTimeInterval: 5.0 target: self
			selector: @selector( ulUpdate ) userInfo: nil
			repeats: YES ];
    
    /* disable manual command button while uploading */
    [ commandButton setEnabled: NO ];

    if ( [ mainWindow isVisible ] ) {
	[ NSApp beginSheet: uploadProgPanel
		modalForWindow: mainWindow
		modalDelegate: self
		didEndSelector: NULL
		contextInfo: nil ];
    }
}

- ( void )ulUpdate
{
    ultime += 5.0;
    [ uploadTimeField setStringValue: [ NSString clockStringFromInteger: ultime ]];
}

- ( void )updateUploadProgress: ( int )endflag
{
    if ( [ uploadQueue count ] > 1 ) {
        NSString	*item = [[[ uploadQueue objectAtIndex: 0 ]
                                    objectForKey: @"fullpath" ] lastPathComponent ];
        
        [ uploadProgName setStringValue: @"" ];
        [ uploadProgName setStringValue: item ];
        [ uploadProgItemsLeft setStringValue: @"" ];
        [ uploadProgItemsLeft setIntValue: [ uploadQueue count ]];
	
	if ( ssh_version < 3.6 ) {
	    [ uploadProgBar incrementBy: 1.0 ];
	    [ uploadProgBar displayIfNeeded ];
	}
	
	[ self removeFirstItemFromUploadQ ];
        item = nil;
    } else if ( [ uploadQueue count ] == 1 ) {
        NSString	*item = [[[ uploadQueue objectAtIndex: 0 ]
                                    objectForKey: @"fullpath" ] lastPathComponent ];
        
        [ uploadProgName setStringValue: @"" ];
        [ uploadProgName setStringValue: item ];
        [ uploadProgItemsLeft setStringValue: @"" ];
        [ uploadProgItemsLeft setIntValue: [ uploadQueue count ]];

	if ( ssh_version < 3.6 ) {
	    [ uploadProgBar setIndeterminate: YES ];
	    [ uploadProgBar startAnimation: nil ];
	    [ uploadProgBar displayIfNeeded ];
	}
	
        [ self removeFirstItemFromUploadQ ];
        item = nil;
    } else {
        [ uploadProgBar stopAnimation: nil ];
        [ uploadProgBar setDoubleValue: 0.0 ];
        [ uploadProgName setStringValue: @"" ];
        [ uploadProgItemsLeft setStringValue: @"" ];
	[ uploadProgInfo setStringValue: @"" ];

        [ uploadProgPanel orderOut: nil ];
        [ NSApp endSheet: uploadProgPanel ];
        
        [ timer invalidate ];
        timer = nil;
        
        /* update remote display to show newly uploaded items */
        [ remoteDirContents release ];
        remoteDirContents = nil;
        remoteDirContents = [[ NSMutableArray alloc ] init ];
        [ remoteBrowser reloadData ];
        
        if ( !endflag )
            [ self writeCommand: lsform ];
        
        /* done uploading, enable manual command button */
        [ commandButton setEnabled: YES ];
    }
}

- ( void )updateUploadProgressBarWithValue: ( double )value
	    amountTransfered: ( NSString * )amount
	    transferRate: ( NSString * )rate
	    ETA: ( NSString * )eta
{
    double		pc_done = value;

    [ uploadProgBar stopAnimation: nil ];
    [ uploadProgBar setIndeterminate: NO ];
    [ uploadProgBar setMinValue: 0.0 ];
    [ uploadProgBar setMaxValue: 100.0 ];
    [ uploadProgBar setDoubleValue: pc_done ];
    [ uploadProgInfo setStringValue: [ NSString stringWithFormat: @"%@ %@ %@", amount, rate, eta ]];
}

- ( IBAction )showLogPanel: ( id )sender
{
    if ( connected ) {
        [ logPanel setTitle: [ NSString stringWithFormat: @"Console: %@@%@",
                            [ userParameters objectForKey: @"user" ],
                            [ userParameters objectForKey: @"rhost" ]]];
    } else {
        [ logPanel setTitle: @"localhost (not connected)" ];
    }

    [ logPanel makeKeyAndOrderFront: nil ];
    [[ manualComField window ] makeFirstResponder: manualComField ];
}

- ( void )clearLog
{
    [ logField setString: @"" ];
}

- ( void )addToLog: ( NSString * )text
{
    [ logField setEditable: YES ];
    [ logField insertText: text ];
    [ logField setEditable: NO ];
}

- ( void )updateHostList
{
    [ remoteHost insertItemWithObjectValue: [ userParameters objectForKey: @"rhost" ] atIndex: 0 ];
    
    if ( [ remoteHost numberOfItems ] < 10 ) {
        [ remoteHost setNumberOfVisibleItems: [ remoteHost numberOfItems ]];
    } else {
        [ remoteHost setNumberOfVisibleItems: 10 ];
    }
}

- ( void )setConnectedWindowTitle
{
    [ mainWindow setTitle: [ NSString stringWithFormat: @"%@@%@",
                            [ userParameters objectForKey: @"user" ],
                            [ userParameters objectForKey: @"rhost" ]]];
}

- ( void )connectionError: ( NSString * )errmsg
{
    if ( strstr(( char * )[ errmsg UTF8String ], "WARNING" ) != NULL ) {
        NSRunAlertPanel( errmsg,
        @"", @"OK", @"", @"" );
    } else {
        NSRunAlertPanel( errmsg, @"", @"OK", @"", @"" );
    }
}

- ( void )sessionError: ( NSString * )errmsg
{
    NSRunAlertPanel( errmsg, @"", NSLocalizedString( @"OK", @"OK" ), @"", @"" );
}

- ( IBAction )showConnectingInterface: ( id )sender
{
    [ mainWindow makeKeyAndOrderFront: nil ];
    
    [ connectingToField setStringValue: [ NSString stringWithFormat:
                NSLocalizedString( @"Connecting to %@...", @"Connecting to %@..." ),
                                        [ userParameters objectForKey: @"rhost" ]]];
    [ connectingProgress setUsesThreadedAnimation: YES ];
    [ connectingProgress startAnimation: nil ];
    [ remoteBox setContentView: nil ];
    [ remoteBox setContentView: connectingView ];
}

- ( void )getContinueQueryForUnknownHost: ( NSDictionary * )hostInfo
{
    [ hostInfo retain ];
    
    [ unauthHostInfo setStringValue: [ hostInfo objectForKey: @"msg" ]];
    [ unauthHostInfo setEditable: NO ];
    [ hostKeyUnauth setStringValue: [ hostInfo objectForKey: @"key" ]];
    [ hostKeyUnauth setEditable: NO ];
    
    [ NSApp beginSheet: verifyConnectSheet modalForWindow: mainWindow
            modalDelegate: self didEndSelector: NULL contextInfo: nil ];
}

- ( BOOL )firstPasswordPrompt
{
    return( firstPasswordPrompt );
}

- ( void )setFirstPasswordPrompt: ( BOOL )first
{
    firstPasswordPrompt = first;
}
    
- ( void )requestPasswordWithPrompt: ( char * )header
{
    [ passHeader setStringValue: [ NSString stringWithUTF8String: header ]];
    
    /* if we find the password in the keychain, don't show the prompt */
    if ( [ self firstPasswordPrompt ] 
            && [ self retrievePasswordFromKeychain ] == YES ) return;
        
    /*
     * if we get another password prompt and we tried using the password
     *  from the keychain, the password is wrong. Let the user know.
     */
    if ( ! [ self firstPasswordPrompt ] && [ self gotPasswordFromKeychain ] ) {
        int			rc;
	NSURL			*url;
        
        rc = NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
                NSLocalizedString( @"The password for this server in your "
                                @"keychain does not seem to be correct. Would "
                                @"you like to open Keychain Access to edit it?",
                                @"The password for this server in your "
                                @"keychain does not seem to be correct. Would "
                                @"you like to open Keychain Access to edit it?" ),
                NSLocalizedString( @"Open Keychain Access", @"Open Keychain Access" ),
                NSLocalizedString( @"Cancel", @"Cancel" ), @"" );
                
        switch ( rc ) {
        case NSAlertDefaultReturn:
	    if ( ! [[ NSWorkspace sharedWorkspace ]
			launchServicesFindApplicationWithBundleID: ( CFStringRef )@"com.apple.keychainaccess"
			foundAppURL: ( CFURLRef * )&url ] ) {
		NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
                    @"Couldn't open Keychain Access", NSLocalizedString( @"OK", @"OK" ), @"", @"" );
	    }
		
            if ( ! [[ NSWorkspace sharedWorkspace ] openURL: url ] ) {
                NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
                    @"Couldn't open Keychain Access", NSLocalizedString( @"OK", @"OK" ), @"", @"" );
            }
            break;
        default:
            break;
        }
    }
    
    [ authProgBar stopAnimation: nil ];
    [ authProgBar retain ];
    [ authProgBar removeFromSuperview ];
    [ passAuthButton setEnabled: YES ];
    [ passWord setEnabled: YES ];
    [ connectingProgress stopAnimation: nil ];
    [ remoteBox setContentView: nil ];
    [ remoteBox setContentView: passView ];
    [[ passWord window ] makeFirstResponder: passWord ];
}

- ( BOOL )retrievePasswordFromKeychain
{
    char		*password;
    OSStatus		error;
    
    if (( password = getpwdfromkeychain( [[ remoteHost stringValue  ] UTF8String ],
                                [[ userName stringValue ] UTF8String ], &error )) == NULL ) {
        if ( error == errSecItemNotFound ) {
            NSLog( @"Keychain item not found" );
        } else {
            NSLog( @"Attempting to retrieve password from keychain return error %d", error );
        }
        return( NO );
    }
    
    [ self setGotPasswordFromKeychain: YES ];
    [ self writeCommand: password ];
    free( password );
    return( YES );
}

- ( void )addPasswordToKeychain
{
    addpwdtokeychain( [[ remoteHost stringValue ] UTF8String ],
                        [[ userName stringValue ] UTF8String ],
                        [[ passWord stringValue ] UTF8String ] );
}

- ( void )setGotPasswordFromKeychain: ( BOOL )rp
{
    gotPasswordFromKeychain = rp;
}

- ( BOOL )gotPasswordFromKeychain
{
    return( gotPasswordFromKeychain );
}

- ( IBAction )sendPassword: ( id )sender
{
    char	pass[ ( _PASSWORD_LEN + 1 ) ] = { 0 };
    
    if ( [[ passWord stringValue ] length ] > _PASSWORD_LEN ) {
	NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
		NSLocalizedString( @"Password is too long.", @"Password is too long." ),
		NSLocalizedString( @"OK", @"OK" ), @"", @"" );
	[ passWord setStringValue: @"" ];
	return;
    }
    
    if ( [ addToKeychainSwitch state ] == NSOnState ) {
        [ self addPasswordToKeychain ];
    }
    
    [ passErrorField setStringValue: @"" ];
    [ passView addSubview: authProgBar ];
    [ authProgBar setUsesThreadedAnimation: YES ];
    [ authProgBar startAnimation: nil ];
    [ passHeader setStringValue: NSLocalizedString( @"Authenticating...",
                                                    @"Authenticating..." ) ];
    [ passAuthButton setEnabled: NO ];

    bcopy( [[ passWord stringValue ] UTF8String ], pass, strlen( [[ passWord stringValue ] UTF8String ] ));
    [ passWord setEnabled: NO ];
    [ self writeCommand: pass ];
    [ passWord setStringValue: @"" ];
}

- ( void )passError
{
    [ passErrorField setStringValue:
            NSLocalizedString( @"Permission denied. Try again.",
                            @"Permission denied. Try again." ) ];
    [ self setFirstPasswordPrompt: NO ];
    [ addToKeychainSwitch setState: NSOffState ];
}

- ( void )enableFavButton: ( NSNotification * )aNotification
{
    id				notobj = [ aNotification object ];
    
    if ( notobj == remoteHost || notobj == userName || notobj == portField
                                    || notobj == loginDirField ) {
        if ( [[ remoteHost stringValue ] length ] ) {
            [ addToFavButton setEnabled: YES ];
        } else {
            [ addToFavButton setEnabled: NO ];
        }
    }
}

- ( IBAction )addToFavorites:( id )sender
{
    if ( [ remoteHost stringValue ] ) {
        NSUserDefaults		*defaults;
        NSMutableArray		*favarray;
        NSArray			*tmp;
        NSDictionary		*dict;
        NSString		*host = [ remoteHost stringValue ];
        NSString		*user = [ userName stringValue ];
        NSString		*port = [ portField stringValue ];
        NSString		*dir = [ loginDirField stringValue ];
        NSString                *opts = [ advAdditionalOptionsField stringValue ];
        int                     ssh1 = [ advForceSSH1Switch state ];
        int                     compress = [ advEnableCompressionSwitch state ];
        
        if ( ! user ) user = @"";
        if ( ! port ) port = @"";
        if ( ! dir ) dir = @"";
        if ( ! opts ) opts = @"";
        
        dict = [ NSMutableDictionary dictionaryWithObjectsAndKeys:
                    @"", @"nick",
                    host, @"host",
                    user, @"user",
                    port, @"port",
                    dir, @"dir",
                    opts, @"options",
                    [ NSNumber numberWithInt: ssh1 ], @"ssh1",
                    [ NSNumber numberWithInt: compress ], @"compress", nil ];
                        
        defaults = [ NSUserDefaults standardUserDefaults ];
        tmp = [ defaults objectForKey: @"Favorites" ];
        favarray = [ NSMutableArray array ];
        if ( tmp ) {
            [ favarray addObjectsFromArray: tmp ];
        }
            
        [ favarray addObject: dict ];
        [[ NSUserDefaults standardUserDefaults ] setObject: favarray forKey: @"Favorites" ];
        [ defaults synchronize ];
        [ self reloadDefaults ];
    }
}

- ( IBAction )selectFromFavorites: ( id )sender
{
    id			fobj;
    NSArray		*favarray;
    int			i = ( [ popUpFavs indexOfSelectedItem ] - 1 );
    
    if ( i < 0 ) return;
    favarray = [[ NSUserDefaults standardUserDefaults ] objectForKey: @"Favorites" ];
    fobj = [ favarray objectAtIndex: i ];
    
    if ( [ fobj isKindOfClass: [ NSString class ]] ) {
        [ remoteHost setStringValue: fobj ];
        return;
    } else if ( [ fobj isKindOfClass: [ NSDictionary class ]] ) {
        [ remoteHost setStringValue: [ fobj objectForKey: @"host" ]];
        [ userName setStringValue: [ fobj objectForKey: @"user" ]];
        [ portField setStringValue: [ fobj objectForKey: @"port" ]];
        [ loginDirField setStringValue: [ fobj objectForKey: @"dir" ]];
        if ( [ fobj objectForKey: @"options" ] ) {
            [ advAdditionalOptionsField setStringValue: [ fobj objectForKey: @"options" ]];
        }
        [ advForceSSH1Switch setState:
                    [[ fobj objectForKey: @"ssh1" ] intValue ]];
        [ advEnableCompressionSwitch setState:
                    [[ fobj objectForKey: @"compress" ] intValue ]];
    }
    [[ remoteHost window ] makeFirstResponder: remoteHost ];
}

- ( IBAction )renameLocalItem: ( id )sender
{
    NSArray             *items = ( dotflag ? localDirContents : dotlessLDir );
    NSString            *name = nil;
    int			row = [ localBrowser selectedRow ];
    
    if ( row < 0 ) {
        return;
    }
    
    if (( name = [[ items objectAtIndex: row ] objectForKey: @"name" ] ) == nil ) {
        return;
    }

    [[ localBrowser selectedCell ] setEditable: YES ];
    [[ localBrowser selectedCell ] setScrollable: YES ];
    [ localBrowser editColumn: 0 row: row withEvent: nil select: YES ];
    [[ localBrowser selectedCell ] setStringValue: [ name lastPathComponent ]];
}

- ( IBAction )renameRemoteItem: ( id )sender
{
    NSArray             *items = ( dotflag ? remoteDirContents : dotlessRDir );
    NSString            *name = nil;
    int			row = [ remoteBrowser selectedRow ];
    
    if ( row < 0 ) {
        return;
    }
    
    if (( name = [[ items objectAtIndex: row ] objectForKey: @"name" ] ) == nil ) {
        return;
    }

    [[ remoteBrowser selectedCell ] setEditable: YES ];
    [[ remoteBrowser selectedCell ] setScrollable: YES ];
    [ remoteBrowser editColumn: 0 row: row withEvent: nil select: YES ];
    [[ remoteBrowser selectedCell ] setStringValue: name ];
}

- ( IBAction )previewItem: ( id )sender
{
    id			browser = [ mainWindow firstResponder ];
    
    if ( ! [ browser isKindOfClass: [ SFTPTableView class ]] ) {
        NSBeep();
        return;
    }
    
    if ( [ browser isEqual: localBrowser ] ) {
        [ self previewLocalItem: sender ];
    } else if ( [ browser isEqual: remoteBrowser ] ) {
        [ self previewRemoteItem: sender ];
    }
}

- ( IBAction )previewLocalItem: ( id )sender
{
    int			row = [ localBrowser selectedRow ];
    NSArray		*items = ( dotflag ? localDirContents : dotlessLDir );
    NSString		*filepath, *extension = nil;
    NSSet		*validExtensions = [ NSSet validImageExtensions ];
    
    if ( row < 0 ) {
        NSBeep();
        return;
    }
    
    filepath = [[ items objectAtIndex: row ] objectForKey: @"name" ];
    extension = [ filepath pathExtension ];
    
    if ( [ validExtensions containsObject: [ extension lowercaseString ]] ) {
        [ self setPreviewedImage: filepath ];
    }
    
    [ self displayPreview ];
}

- ( IBAction )previewRemoteItem: ( id )sender
{
    int			row = [ remoteBrowser selectedRow ];
    NSArray		*items = ( dotflag ? remoteDirContents : dotlessRDir );
    NSSet		*validExtensions = [ NSSet validImageExtensions ];
    NSString		*extension = nil;
    NSString		*filepath = nil, *filename = nil, *tmppath = nil;
    NSData              *rawdata = nil;
    NSArray		*previews = [ self cachedPreviews ];
    
    if ( row < 0 ) {
        NSBeep();
        return;
    }
    
    rawdata = [[ items objectAtIndex: row ] objectForKey: @"NameAsRawBytes" ];
    filename = [[ items objectAtIndex: row ] objectForKey: @"name" ];
    extension = [ filename pathExtension ];
    filepath = [ NSString stringWithFormat: @"%@/%@", remoteDirPath, filename ];
    
    if ( previews != nil ) {
        int		i;
        
        for ( i = 0; i < [ previews count ]; i++ ) {
            if ( [[[ previews objectAtIndex: i ]
                    objectForKey: @"RemotePath" ] isEqualToString: filepath ] ) {
                [ self setPreviewedImage: [[ previews objectAtIndex: i ]
                                                objectForKey: @"LocalPath" ]];
                [ self displayPreview ];
                return;
            }
        }
    }
    
    if ( ! [ validExtensions containsObject: [ extension lowercaseString ]] ) {
        [ self displayPreview ];
        return;
    }
    
    tmppath = [[ NSFileManager defaultManager ]
                    makeTemporaryDirectoryWithMode: ( mode_t )0700 ];
                    
    if ( tmppath == nil ) {
        NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
            @"mkdir: %s", NSLocalizedString( @"OK", @"OK" ), @"", @"",
            strerror( errno ));
        return;
    }
    
    tmppath = [ tmppath stringByAppendingPathComponent: filename ];
    
    [ self setPreviewedImage: tmppath ];
    [ self addToCachedPreviews: [ NSDictionary dictionaryWithObjectsAndKeys:
                filepath, @"RemotePath",
                tmppath, @"LocalPath", nil ]];
    
    [ downloadQueue addObject:
            [ NSDictionary dictionaryWithObjectsAndKeys:
                rawdata, @"rpath", tmppath, @"lpath", nil ]];
    [ self writeCommand: ( void * )" " ];
}

- ( void )displayPreview
{
    NSImage			*image = nil;
    NSString			*name = nil, *path = nil;
    NSSize			imageSize;
    NSRect			originalPanelFrame;
    NSPoint			cellorigin;
    id				table = [ mainWindow firstResponder ];
    int				row;
        
    if ( ! [ table isKindOfClass: [ SFTPTableView class ]] ) {
        return;
    }
    
    if (( row = [ table selectedRow ] ) < 0 ) {
        NSBeep();
        return;
    }
    
    if ( [ self previewedImage ] == nil ) {
        NSArray			*items = nil;
        NSString		*extension;

        if ( [ table isEqual: localBrowser ] ) {
            items = ( dotflag ? localDirContents : dotlessLDir );
            name = [[ items objectAtIndex: row ] objectForKey: @"name" ];
            image = [[ NSWorkspace sharedWorkspace ] iconForFile: name ];
        } else if ( [ table isEqual: remoteBrowser ] ) {
            items = ( dotflag ? remoteDirContents : dotlessRDir );
            name = [[ items objectAtIndex: row ] objectForKey: @"name" ];
            extension = [ name pathExtension ];
            
            if ( [ extension isEqualToString: @"" ] ) {
                if ( [[[ items objectAtIndex: row ] objectForKey: @"perm" ]
                            characterAtIndex: 0 ] == 'd' ) {
                    image = [[ NSWorkspace sharedWorkspace ] iconForFileType: @"'fldr'" ];
                } else {
                    image = [[ NSWorkspace sharedWorkspace ] iconForFileType: @"'doc '" ];
                }
            } else {
                image = [[ NSWorkspace sharedWorkspace ] iconForFileType: extension ];
            }
        }
        [ image setScalesWhenResized: YES ];
        [ image setSize: NSMakeSize( 128.0, 128.0 ) ];
        [ image retain ];
    } else {
        image = [[ NSImage alloc ] initWithContentsOfFile: [ self previewedImage ]];
        
        if ( image == nil ) {
            NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
                    NSLocalizedString( @"Couldn't create preview of %@",
                                        @"Couldn't create preview of %@" ),
                    NSLocalizedString( @"OK", @"OK" ), @"", @"",
                    [[ self previewedImage ] lastPathComponent ] );
            return;
        }
        path = [ self previewedImage ];
        name = [ path lastPathComponent ];
    }
    originalPanelFrame = [ imagePreviewPanel frame ];
    cellorigin = [ table originOfSelectedCell ];
    
    imageSize = [ image size ];
    [ image setScalesWhenResized: YES ];

    [ imagePreviewPanel setTitle: [ NSString stringWithFormat: @"Preview: %@", name ]];
    [ imagePreviewTextField setStringValue:
            [ NSString stringWithFormat:
                    NSLocalizedString( @"Image size: %.0f x %.0f", @"Image size: %.0f x %.0f" ),
                    imageSize.width, imageSize.height ]];
                    
    [ imagePreview setImage: image ];
    [ imagePreview setImageLocationPath: path ];
                        
    if ( ! [ imagePreviewPanel isVisible ] ) {
        [ imagePreviewBox setContentView: nil ];
        [ imagePreviewPanel zoomFromRect: NSMakeRect( cellorigin.x, cellorigin.y, 1.0, 1.0 )
                                toRect: originalPanelFrame ];
        [ imagePreviewBox setContentView: imagePreviewView ];
    }
    [ image release ];
    [ self setPreviewedImage: nil ];
}

/* open local items with default application */
- ( IBAction )openItem: ( id )sender
{
    UMFileLauncher	*launcher;
    id			dsrc;
    int			row = [ localBrowser selectedRow ];
    
    if ( row < 0 ) {
        return;
    }
    
    launcher = [[ UMFileLauncher alloc ] init ];
    dsrc = ( dotflag ? localDirContents : dotlessLDir );
    
    [ launcher openFile: [[ dsrc objectAtIndex: row ] objectForKey: @"name" ]
                withApplication: nil ];
    [ launcher release ];
}

/* open in Editor */
- ( IBAction )editFile: ( id )sender
{
    id			table = [ mainWindow firstResponder ];
    
    if ( ! [ table isKindOfClass: [ SFTPTableView class ]] ) {
        return;
    }
    
    if ( [ table isEqual: localBrowser ] ) {
        [ self openLocalFileInEditor: sender ];
    } else if ( [ table isEqual: remoteBrowser ] ) {
        [ self openRemoteFileInEditor: sender ];
    }
}

- ( IBAction )openLocalFileInEditor: ( id )sender
{
    FSRef		editorref;
    OSType		creator = 'R*ch';
    unsigned int	row = [ localBrowser selectedRow ];
    NSString		*filepath = [[ ( dotflag ? localDirContents : dotlessLDir )
                                        objectAtIndex: row ] objectForKey: @"name" ];
    NSString		*editorpath;
    NSString		*editor = [[ NSUserDefaults standardUserDefaults ] objectForKey: @"ODBTextEditor" ];
    
    if ( editor == nil ) {
	editor = @"BBEdit.app";
    }
    
    if ( [[ NSWorkspace sharedWorkspace ]
		launchServicesFindApplication: ( CFStringRef )editor
		foundAppRef: &editorref ] == NO ) {
        if ( [[ NSWorkspace sharedWorkspace ]
                launchServicesFindApplicationWithCreatorType: creator
                foundAppRef: &editorref  ] == NO ) {
            NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
                    NSLocalizedString( @"Couldn't find %@ to launch %@.",
                                        @"Couldn't find %@ to launch %@." ),
                    NSLocalizedString( @"OK", @"OK" ), @"", @"",
                                        editor, [ filepath lastPathComponent ] );
            return;
        }
    }
    
    if (( editorpath = [ NSString stringWithFSRef: &editorref ] ) == nil ) {
	NSLog( @"failed to convert FSRef to NSString" );
	return;
    }
    
    if ( [[ NSWorkspace sharedWorkspace ] openFile: filepath
		    withApplication: editorpath andDeactivate: YES ] == NO ) {
	NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
		@"Couldn't open %@ in %@", NSLocalizedString( @"OK", @"OK" ),
		@"", @"", [ filepath lastPathComponent ], [ editorpath lastPathComponent ] );
	return;
    }
}

- ( IBAction )openRemoteFileInEditor: ( id )sender
{
    int			row = [ remoteBrowser selectedRow ];
    NSDictionary	*item = [ ( dotflag ? remoteDirContents : dotlessRDir ) objectAtIndex: row ];
    NSData              *data = [ item objectForKey: @"NameAsRawBytes" ];
    NSString		*filename = [ item objectForKey: @"name" ], *tmppath = nil;
    NSString            *objcFilepath = nil;
    char                filepath[ MAXPATHLEN ], name[ MAXPATHLEN ] = { 0 };
    
    tmppath = [[ NSFileManager defaultManager ]
                makeTemporaryDirectoryWithMode: ( mode_t )0700 ];
    
    if ( tmppath == nil ) {
        NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
            @"mkdir: %s", NSLocalizedString( @"OK", @"OK" ), @"", @"",
            strerror( errno ));
        return;
    }

    memcpy( name, [ data bytes ], [ data length ] );
    tmppath = [ tmppath stringByAppendingPathComponent: filename ];
    if ( snprintf( filepath, MAXPATHLEN, "%s/%s",
                [ remoteDirPath UTF8String ], name ) >= MAXPATHLEN ) {
        NSLog( @"%@/%s: path too long", remoteDirPath, name );
        return;
    }
    
    objcFilepath = [ NSString stringWithBytesOfUnknownEncoding: filepath
                                length: strlen( filepath ) ];
    
    [ self addToEditedDocuments: tmppath
		    remotePath: objcFilepath ];
    
    [ downloadQueue addObject: [ NSDictionary dictionaryWithObjectsAndKeys:
            [ NSData dataWithBytes: filepath length: strlen( filepath ) ], @"rpath",
            tmppath, @"lpath", nil ]];
    [ self writeCommand: " " ];
}

- ( void )ODBEditFile: ( NSString * )filepath remotePath: ( NSString * )remotePath
{
    int                 i;
    OSErr		err = ( OSErr )0;
    AEKeyword		keyServerID = 'Fugu';
    NSString		*appname = nil, *failedCall = @"";
    NSString            *bundleID = nil, *sig = nil;
    OSType		creator = 'R*ch', ct;
    const char		*custompath;
    FSRef		fileref, editorref;
    AERecord		rec = { typeNull, NULL };
    NSBundle            *bundle = [ NSBundle bundleForClass: [ self class ]];
    NSDictionary        *dict = [ NSDictionary dictionaryWithContentsOfFile:
                                    [ bundle pathForResource: @"ODBEditors" ofType: @"plist" ]];
    NSDictionary        *odbEditorInfo = nil;

    if (( appname = [[ NSUserDefaults standardUserDefaults ]
			objectForKey: @"ODBTextEditor" ] ) == nil ) {
	appname = @"BBEdit";
    }

    /* find the entry for the given editor */
    for ( i = 0; i < [[ dict objectForKey: @"ODBEditors" ] count ]; i++ ) {
        if ( [[[[ dict objectForKey: @"ODBEditors" ] objectAtIndex: i ]
                        objectForKey: @"ODBEditorName" ] isEqualToString: appname ] ) {
            odbEditorInfo = [[ dict objectForKey: @"ODBEditors" ] objectAtIndex: i ];
            bundleID = [ odbEditorInfo objectForKey: @"ODBEditorBundleID" ];
            sig = [ odbEditorInfo objectForKey: @"ODBEditorCreatorCode" ];
            break;
        }
    }
    if ( i >= [[ dict objectForKey: @"ODBEditors" ] count ] ) {
        /* XXX error handling */
        return;
    }

    /* check to see if the editor is run on the CLI */
    if ( [[ odbEditorInfo objectForKey: @"ODBEditorLaunchStyle" ] intValue ] == 1 ) {
        UMFileLauncher          *launch = [[ UMFileLauncher alloc ] init ];
        NSString                *editorPath = [ odbEditorInfo objectForKey: @"ODBEditorPath" ];
        
        [[ NSAppleEventManager sharedAppleEventManager ] setEventHandler: self
	    andSelector: @selector( handleODBFileClosedEvent:andReplyWithEvent: )
	    forEventClass: kODBEditorSuite andEventID: kAEClosedFile ];
	    
        [[ NSAppleEventManager sharedAppleEventManager ] setEventHandler: self
                andSelector: @selector( handleODBFileModifiedEvent:andReplyWithEvent: )
                forEventClass: kODBEditorSuite andEventID: kAEModifiedFile ];
                
        if ( ! [ launch externalEditFile: filepath withCLIEditor: editorPath
                            contextInfo: ( void * )remotePath ] ) {
            NSLog( @"FAILED" );
        }
        [ launch release ];
        return;
    }
    
    if ( sig ) {
        ct = *( OSType * )[ sig UTF8String ];
    } else {
        ct = kLSUnknownCreator;
    }
	
    if ( [ filepath makeFSRefRepresentation: &fileref ] != noErr ) {
	NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
		@"Failed to create FSRef from %@: error %d",
		NSLocalizedString( @"OK", @"OK" ), @"", @"", filepath, err );
	return;
    }
     
    if ( ! [[ NSWorkspace sharedWorkspace ]
                launchServicesFindApplicationForCreatorType: ct
                bundleID: ( CFStringRef )bundleID appName: ( CFStringRef )appname
                foundAppRef: &editorref foundAppURL: NULL ] ) {
        if ( [[ NSWorkspace sharedWorkspace ]
                        launchServicesFindApplicationWithCreatorType: creator
                        foundAppRef: &editorref  ] == NO ) {
            NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
                        NSLocalizedString( @"Couldn't find %@ to launch %@.",
                                            @"Couldn't find %@ to launch %@." ),
                        NSLocalizedString( @"OK", @"OK" ), @"", @"",
                                            appname, [ filepath lastPathComponent ] );
            return;
        }
    }
    
    if (( err = AECreateList( NULL, 0, TRUE, &rec )) != 0 ) {
	failedCall = @"AECreateList";
	goto AECallErr;
    }
    
    if (( err = AEPutParamPtr( &rec, keyFileSender,
			    typeType, ( Ptr )&keyServerID, sizeof( AEKeyword ))) != 0 ) {
	failedCall = @"AEPutParamPtr";
	goto AECallErr;
    }
    
    custompath = [[ NSString stringWithFormat: @"sftp://%@@%@%@", [ userName stringValue ],
				    [ remoteHost stringValue ], remotePath ] UTF8String ];
				    
    if (( err = AEPutParamPtr( &rec, keyFileCustomPath,
			    typeChar, custompath, strlen( custompath ))) != 0 ) {
	failedCall = @"AEPutParamPtr";
	goto AECallErr;
    }

    if ( [ remotePath length ] >= MAXPATHLEN ) {
	NSLog( @"%@: path exceeds MAXPATHLEN!", remotePath );
	return;
    }
    
    if (( err = AEPutParamPtr( &rec, keyFileSenderToken,
		typeChar, [ remotePath UTF8String ], strlen( [ remotePath UTF8String ] ))) != 0 ) {
	failedCall = @"AEPutParamPtr";
	goto AECallErr;
    }
    
    [[ NSAppleEventManager sharedAppleEventManager ] setEventHandler: self
	    andSelector: @selector( handleODBFileClosedEvent:andReplyWithEvent: )
	    forEventClass: kODBEditorSuite andEventID: kAEClosedFile ];
	    
    [[ NSAppleEventManager sharedAppleEventManager ] setEventHandler: self
	    andSelector: @selector( handleODBFileModifiedEvent:andReplyWithEvent: )
	    forEventClass: kODBEditorSuite andEventID: kAEModifiedFile ];
    
    if ( [[ NSWorkspace sharedWorkspace ] launchServicesOpenFileRef: &fileref
					withApplicationRef: &editorref
					passThruParams: &rec
					launchFlags: kLSLaunchDefaults ] == NO ) {
	goto LaunchFailed;
    }
    
    /* successful */
    if ( rec.dataHandle != NULL ) {
	( void )AEDisposeDesc( &rec );
    }
    return;
    
AECallErr:
    NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
		@"%@ failed: error %d", NSLocalizedString( @"OK", @"OK" ),
		@"", @"", failedCall, err );
    if ( rec.dataHandle != NULL ) {
	( void )AEDisposeDesc( &rec );
    }
    return;
    
LaunchFailed:
    NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
		@"Failed to open %@ with %@.", NSLocalizedString( @"OK", @"OK" ),
		@"", @"", [ filepath lastPathComponent ], appname );
    return;
}

- ( void )testHandleEvent: ( NSAppleEventDescriptor * )inEvent
            replyEvent: ( NSAppleEventDescriptor * )replyEvent
{
    DescType			indtype = [ inEvent descriptorType ];
    AEEventID			eid = [ inEvent eventID ];
    NSAppleEventDescriptor      *fssDesc;
    NSString                    *filename = nil;

    switch ( eid ) {
    case kAEClosedFile:
        NSLog( @"received kAEClosedFile event" );
        break;
        
    case kAEModifiedFile:
        NSLog( @"received kAEModifiedFile event" );
        break;
        
    default:
        NSLog( @"??????" );
        break;
    }
    
    if (( fssDesc = [ inEvent paramDescriptorForKeyword: keyDirectObject ] ) == nil ) {
        NSLog( @"no descriptor for keyDirectObject" );
        return;
    }
    
    indtype = [ fssDesc descriptorType ];
    NSLog( @"indtype: %s", &indtype );
    fssDesc = [ fssDesc coerceToDescriptorType: typeFSS ];
    
    if ( fssDesc == nil ) {
        NSBeep();
        return;
    }
    
    filename = [ NSString stringWithFSSpec: ( FSSpec * )[[ fssDesc data ] bytes ]];
    NSLog( @"filename: %@", filename );
}

- ( void )handleODBFileClosedEvent: ( NSAppleEventDescriptor * )inEvent
	    andReplyWithEvent: ( NSAppleEventDescriptor * )replyEvent
{
    DescType			indtype = [ inEvent descriptorType ];
    AEEventID			eid = [ inEvent eventID ];
    NSAppleEventDescriptor	*fssDesc;
    NSString			*filename = nil;
    
    if ( eid != kAEClosedFile ) {
        NSLog( @"Unknown event (%s) received", &eid );
        return;
    }
    
    if (( fssDesc = [ inEvent paramDescriptorForKeyword: keyDirectObject ] ) == nil ) {
        NSLog( @"no descriptor for keyDirectObject" );
        return;
    }
    
    indtype = [ fssDesc descriptorType ];
    
    if ( indtype != typeFSS ) {
        fssDesc = [ fssDesc coerceToDescriptorType: typeFSS ];
        if ( fssDesc == nil ) {
            NSLog( @"Couldn't coerce descriptor to typeFSS" );
            return;
        }
    }
    
    filename = [ NSString stringWithFSSpec: ( FSSpec * )[[ fssDesc data ] bytes ]];
    [ self performSelector: @selector( removeFromEditedDocuments: )
            withObject: filename afterDelay: 1.0 ];

    if ( [[ self editedDocuments ] count ] == 0 ) {
        [[ NSAppleEventManager sharedAppleEventManager ]
                removeEventHandlerForEventClass: kODBEditorSuite
                andEventID: kAEClosedFile ];
    }
    
    if ( [[ NSUserDefaults standardUserDefaults ]
                integerForKey: @"PostEditBehaviour" ] == 0 ) {
        [ NSApp activateIgnoringOtherApps: YES ];
    }
}

- ( void )handleODBFileModifiedEvent: ( NSAppleEventDescriptor * )inEvent
	    andReplyWithEvent: ( NSAppleEventDescriptor * )replyEvent
{
    DescType			indtype = [ inEvent descriptorType ];
    AEEventID			eid = [ inEvent eventID ];
    NSAppleEventDescriptor	*desc;
    NSData			*descdata;
    NSURL                       *fileURL = nil;
    NSString			*filename = nil;
    char			remotepath[ MAXPATHLEN ] = { 0 };
    
    if ( eid != kAEModifiedFile ) {
        NSLog( @"Unexpected event type (%s) in FMod handler.", &eid );
        return;
    }
    
    if (( desc = [ inEvent descriptorForKeyword: keyNewLocation ] ) == nil ) {
        if (( desc = [ inEvent descriptorForKeyword: keyDirectObject ] ) == nil ) {
            NSLog( @"no descriptor for keyDirectObject" );
            return;
        }
    }
    
    if (( indtype = [ desc descriptorType ] ) != typeFileURL ) {
        if (( desc = [ desc coerceToDescriptorType: typeFileURL ] ) == nil ) {
            NSLog( @"coerceToDescriptorType typeFileURL failed." );
            return;
        }
    }
    
    if (( descdata = [ desc data ] ) == nil ) {
        NSLog( @"no data" );
        return;
    }

    fileURL = ( NSURL * )CFURLCreateWithBytes( kCFAllocatorDefault,
                            [ descdata bytes ], [ descdata length ],
                            kCFStringEncodingUTF8, NULL );
    if ( ! fileURL ) {
        NSLog( @"CFURLCreateWithBytes failed." );
        return;
    }
    [ fileURL autorelease ];
    filename = [ fileURL path ];

    if (( desc = [ inEvent descriptorForKeyword: keySenderToken ] ) == nil ) {
        NSLog( @"No sender token" );
        NSBeep();
        return;
    }
    
    if ( [[ desc data ] length ] >= MAXPATHLEN ) {
        NSLog( @"Path too long" );
        return;
    } else {
        /* Make sure the remote path always gets the most recent name of the edited file */
        char                *p = NULL;
        
        strcpy( remotepath, [[ desc data ] bytes ] );
        if (( p = strrchr( remotepath, '/' )) == NULL ) {
            NSLog( @"No slash in remote path" );
            return;
        }
        *++p = '\0';
        
        if (( strlen( remotepath ) + [[ filename lastPathComponent ] length ] + 1 )
                    >= MAXPATHLEN ) {
            NSLog( @"%s%@: too long", remotepath, [ filename lastPathComponent ] );
            return;
        }
        strcat( remotepath, [[ filename lastPathComponent ] UTF8String ] );
    }

    [ uploadQueue addObject: [ NSDictionary dictionaryWithObjectsAndKeys:
                        [ NSNumber numberWithInt: 0 ], @"isdir",
                        filename, @"fullpath",
                        [ NSString stringWithUTF8String: remotepath ], @"pathfrombase", nil ]];
    [ self writeCommand: " " ];    
}

- ( IBAction )getInfo: ( id )sender
{
    NSDictionary	*attribDict;
    NSDictionary	*rAttribDict;
    NSString		*fullPath;
    NSArray		*items = nil;
    id			activeTableView;
    CFStringRef		type;
    CFURLRef		url;
    OSStatus		status;
    
    if ( ! [ infoPanel isVisible ] ) {
        [ infoPanel makeKeyAndOrderFront: nil ];
    }
    
    activeTableView = [ mainWindow firstResponder ];
        
    if ( [ activeTableView isEqual: localBrowser ] || ! connected ) {
        [ infoTabView selectTabViewItemWithIdentifier: @"local" ];
    } else {
        [ infoTabView selectTabViewItemWithIdentifier: @"remote" ];
    }
    
    items = ( dotflag ? localDirContents : dotlessLDir );
    if ( [ localBrowser selectedRow ] == -1 ) {
        fullPath = localDirPath;
        attribDict = [[ SFTPNode sharedInstance ]
                            statInformationForPath: fullPath ];
    } else {
        fullPath = [[ items objectAtIndex: [ localBrowser selectedRow ]] objectForKey: @"name" ];
        attribDict = [ items objectAtIndex: [ localBrowser selectedRow ]];
    }
    
    if ( ! [ fullPath isEqualToString: [ whereField stringValue ]] ) {
        [ infoPathField setStringValue: [ fullPath lastPathComponent ]];
        [ whereField setStringValue: fullPath ];
        
        [ largeIcon setImage: [[ NSWorkspace sharedWorkspace ]
                iconForFile: fullPath ]];
        [ self localCheckSetup: [ attribDict objectForKey: @"perm" ]];
	
	url = CFURLCreateFromFileSystemRepresentation( kCFAllocatorDefault,
		    ( const UInt8 * )[ fullPath fileSystemRepresentation ],
		    strlen( [ fullPath fileSystemRepresentation ] ), false );
	if ( url ) {
	    if (( status = LSCopyKindStringForURL( url, &type )) != noErr ) {
		NSLog( @"LSCopyKindStringForURL failed: error %d", ( int )status );
		[ typeField setStringValue: [ attribDict objectForKey: @"type" ]];
	    } else {
		[ typeField setStringValue: ( NSString * )type ];
		CFRelease( type );
	    }
	    CFRelease( url );
	}
                
        [ ownerField setStringValue: [ attribDict objectForKey: @"owner" ]];
        [ groupField setStringValue: [ attribDict objectForKey: @"group" ]];
        [ sizeField setStringValue: [ NSString stringWithFormat: @"%@ (%@ bytes)",
                                    [[ attribDict objectForKey: @"size" ] descriptiveSizeString ],
                                    [ attribDict objectForKey: @"size" ]]];
        [ modDateField setObjectValue: [ attribDict objectForKey: @"date" ]];
        [ permField setStringValue: [ attribDict objectForKey: @"perm" ]];
    }
    
    if ( !connected ) return;
    
    rAttribDict = (( dotflag ) ? [[ remoteDirContents objectAtIndex:
                                                    [ remoteBrowser selectedRow ]] copy ] :
                                [[ dotlessRDir objectAtIndex: [ remoteBrowser selectedRow ]] copy ] );

    [ rInfoPathField setStringValue: [ rAttribDict objectForKey: @"name" ]];
    [ rWhereField setStringValue:
            [ NSString stringWithFormat: @"%@/%@", remoteDirPath,
            [ rAttribDict objectForKey: @"name" ]]];
    
    [ rIcon setImage: [ NSImage iconForType:
            [[ rAttribDict objectForKey: @"name" ] pathExtension ]]];

    [ rOwnerField setStringValue: [ rAttribDict objectForKey: @"owner" ]];
    
    [ rGroupField setStringValue: [ rAttribDict objectForKey: @"group" ]];
    
    [ rSizeField setStringValue: [ NSString stringWithFormat: @"%@ (%@ bytes)",
                                    [[ rAttribDict objectForKey: @"size" ] descriptiveSizeString ],
                                    [ rAttribDict objectForKey: @"size" ]]];
    [ rModDateField setObjectValue: [ rAttribDict objectForKey: @"date" ]];

    [ rPermField setStringValue: [[ rAttribDict objectForKey: @"perm" ] octalRepresentation ]];
    [ self remoteCheckSetup: [ rAttribDict objectForKey: @"perm" ]];
    [ rTypeField setStringValue: [ rAttribDict objectForKey: @"type" ]];
    if ( [[ rAttribDict objectForKey: @"type" ] isEqualToString: @"directory" ] ) {
        [ rIcon setImage: nil ];
        [ rIcon setImage: [[ NSWorkspace sharedWorkspace ] iconForFileType: @"'fldr'" ]];
    }
    [ rAttribDict release ];
}

- ( void )localCheckSetup: ( NSString * )octalmode
{
    int			ow, own, gr, grp, ot, oth;
    
    /* switch all off first */
    [ loReadSwitch setState: NSOffState ];
    [ loWriteSwitch setState: NSOffState ];
    [ loExecSwitch setState: NSOffState ];
    [ lgReadSwitch setState: NSOffState ];
    [ lgWriteSwitch setState: NSOffState ];
    [ lgExecSwitch setState: NSOffState ];
    [ laReadSwitch setState: NSOffState ];
    [ laWriteSwitch setState: NSOffState ];
    [ laExecSwitch setState: NSOffState ];
    
    ow = own = ( [ octalmode characterAtIndex: 1 ] - '0' );
    gr = grp = ( [ octalmode characterAtIndex: 2 ] - '0' );
    ot = oth = ( [ octalmode characterAtIndex: 3 ] - '0' );
    
    if (( own = ( own - 4 )) >= 0 )
                    [ loReadSwitch setState: NSOnState ];
    if (( own = ( own - 2 )) >= 0 || ( own == -2 && ow == 2 ) || ( own == -3 && ow == 3 ))
                    [ loWriteSwitch setState: NSOnState ];
    if (( own = ( own - 1 )) >= 0 || own == -2 || own == -4 || own == -6 )
                    [ loExecSwitch setState: NSOnState ];
    
    if (( grp = ( grp - 4 )) >= 0 )
                    [ lgReadSwitch setState: NSOnState ];
    if (( grp = ( grp - 2 )) >= 0 || ( grp == -2 && gr == 2 ) || ( grp == -3 && gr == 3 ))
                    [ lgWriteSwitch setState: NSOnState ];
    if (( grp = ( grp - 1 )) >= 0 || grp == -2 || grp == -4 || grp == -6 )
                    [ lgExecSwitch setState: NSOnState ];
    
    if (( oth = ( oth - 4 )) >= 0 )
                    [ laReadSwitch setState: NSOnState ];
    if (( oth = ( oth - 2 )) >= 0 || ( oth == -2 && ot == 2 ) || ( oth == -3 && ot == 3 ))
                    [ laWriteSwitch setState: NSOnState ];
    if (( oth = ( oth - 1 )) >= 0 || oth == -2 || oth == -4 || oth == -6 )
                    [ laExecSwitch setState: NSOnState ];
}

- ( void )remoteCheckSetup: ( NSString * )permissions
{
    int			i;
    
    for ( i = 0; i < [ rSwitchArray count ]; i++ ) {
        [[ rSwitchArray objectAtIndex: i ] setState: NSOffState ];
    }
    
    for ( i = 1; i < 4; i++ ) {
        switch( [ permissions characterAtIndex: i ] ) {
        case 'r':
            [ roReadSwitch setState: NSOnState ];
            break;
        case 'w':
            [ roWriteSwitch setState: NSOnState ];
            break;
        case 'x':
        case 's':
            [ roExecSwitch setState: NSOnState ];
            break;
        }
    }
    
    for ( i = 4; i < 7; i++ ) {
        switch( [ permissions characterAtIndex: i ] ) {
        case 'r':
            [ rgReadSwitch setState: NSOnState ];
            break;
        case 'w':
            [ rgWriteSwitch setState: NSOnState ];
            break;
        case 'x':
        case 's':
            [ rgExecSwitch setState: NSOnState ];
            break;
        }
    }
    
    for ( i = 7; i < 10; i++ ) {
        switch( [ permissions characterAtIndex: i ] ) {
        case 'r':
            [ raReadSwitch setState: NSOnState ];
            break;
        case 'w':
            [ raWriteSwitch setState: NSOnState ];
            break;
        case 'x':
        case 't':
            [ raExecSwitch setState: NSOnState ];
            break;
        }
    }
}

- ( IBAction )toggleAdvConnectionView: ( id )sender
{
    if ( [ sender isKindOfClass: [ NSButton class ]] ) {
	if ( [[ sender image ] isEqual: [ NSImage imageNamed: @"righttriangle.png" ]] ) {
	    [ sender setImage: [ NSImage imageNamed: @"downtriangle.png" ]];
	} else {
	    [ sender setImage: [ NSImage imageNamed: @"righttriangle.png" ]];
	}
    }
    
    if ( ! [[ advConnectionBox contentView ] isEqual: advConnectionView ] ) {
        [ advConnectionBox setContentView: nil ];
        [ advConnectionBox setContentView: advConnectionView ];
    } else {
        [ advConnectionBox setContentView: nil ];
    }
}

- ( IBAction )sftpConnect: ( id )sender
{
    NSString		*portString;
    NSArray		*params, *recent;
    NSMutableArray	*tmp;
    int			i, port = 0, len;
    
    [ connectButton setEnabled: NO ];
    
    portString = [ portField stringValue ];
    len = [ portString length ];
    if ( len ) {
        port = [ portString intValue ];
        if ( port == 0 ) {
            NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
                    NSLocalizedString( @"Invalid port number.", @"Invalid port number." ),
                    NSLocalizedString( @"OK", @"OK" ), @"", @"" );
            goto INVALID_CONNECTION_SETTINGS;
        }
    }
    
    if ( [[ userName stringValue ] length ]
            && [[ remoteHost stringValue ] length ] ) {
        userParameters = [[ NSMutableDictionary alloc ] initWithObjectsAndKeys:
                    [ userName stringValue ], @"user",
                    [ remoteHost stringValue ], @"rhost", nil ];
    } else {
        NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
            NSLocalizedString( @"You must provide a username and server address to continue.",
                @"You must provide a username and server address to continue." ),
            NSLocalizedString( @"OK", @"OK" ), @"", @"" );
        goto INVALID_CONNECTION_SETTINGS;
    }
    
    params = [ NSArray array ];
    
    if ( [ advForceSSH1Switch state ] == NSOnState ) {
        NSArray		*tmp = [ NSArray array ];
        
        tmp = [ tmp arrayByAddingObjectsFromArray: params ];
        params = nil;
        params = [ NSArray arrayWithObject: @"-1" ];
        params = [ params arrayByAddingObjectsFromArray: tmp ];
    }
    
    if ( [ advEnableCompressionSwitch state ] == NSOnState ) {
	NSArray		*tmp = [ NSArray array ];
	
	tmp = [ tmp arrayByAddingObjectsFromArray: params ];
	params = nil;
	params = [ NSArray arrayWithObject: @"-C" ];
	params = [ params arrayByAddingObjectsFromArray: tmp ];
    }
    
    /* only specify port if given to us, so we don't override .ssh/config */
    if ( port ) {
        params = [ params arrayByAddingObject: [ NSString stringWithFormat: @"-oPort=%d", port ]];
    }
    
    if ( [[ advAdditionalOptionsField stringValue ] length ] ) {
        params = [ params arrayByAddingObjectsFromArray:
                    [[ advAdditionalOptionsField stringValue ] componentsSeparatedByString: @" " ]];
    }
    
    params = [ params arrayByAddingObject:
                [ NSString stringWithFormat: @"%@@%@", [ userParameters objectForKey: @"user" ],
                [ userParameters objectForKey: @"rhost" ]]];
    
    switch ( sshversion()) {
    case SFTP_VERSION_UNSUPPORTED:
        /* Let's not pretend we support SSH.com's sftp client */
        NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
                @"Unsupported version of sftp.",
                NSLocalizedString( @"OK", @"OK" ), @"", @"" );
        goto INVALID_CONNECTION_SETTINGS;
        break;
        
    case SFTP_LS_LONG_FORM:
        lsform = "ls -l";
        break;
        
    case SFTP_LS_EXTENDED_LONG_FORM:
        lsform = "ls -la";
        break;
    
    case SFTP_LS_SHORT_FORM:
    default:
        lsform = "ls";
        break;
    }
    
    [ self setFirstPasswordPrompt: YES ];
    
    remoteDirContents = [[ NSMutableArray alloc ] init ];
    dotlessRDir	= [[ NSMutableArray alloc ] init ];
    remoteDirPath = [[ NSString alloc ] init ];
    [ tServer connectToServerWithParams: params fromController: self ];
    [ self showConnectingInterface: nil ];
    
    recent = [ remoteHost objectValues ];
    tmp = [ NSMutableArray array ];
    for ( i = 0; i < [ recent count ]; i++ ) {
        if ( ! [ tmp containsObject: [ recent objectAtIndex: i ]] ) {
            [ tmp addObject: [ recent objectAtIndex: i ]];
        }
    }
    
    [[ NSUserDefaults standardUserDefaults ] setObject: tmp
            forKey: @"RecentServers" ];
    [ remoteHost removeAllItems ];
    [ remoteHost addItemsWithObjectValues:
        [[ NSUserDefaults standardUserDefaults ] objectForKey: @"RecentServers" ]];
    return;
    
INVALID_CONNECTION_SETTINGS:
    [ connectButton setEnabled: YES ];
    return;
}

- ( BOOL )handleChangedText: ( NSString * )newstring forTable: ( SFTPTableView * )table
            column: ( int )column
{
    NSMutableArray	*items;
    int			row = [ table editedRow ];
    
    if ( row < 0 ) {
        NSBeep();
        return( NO );
    }
    
    if ( [ table isEqual: localBrowser ] ) {
        NSString		*newpath;
        NSDictionary		*dict;
        
        if ( ! [ newstring length ] ) {
            return( NO );
        }
    
        items = ( dotflag ? localDirContents : dotlessLDir );
        dict = [ items objectAtIndex: row ];
        newpath = [ NSString stringWithFormat: @"%@/%@",
                        [[ dict objectForKey: @"name" ]
                                stringByDeletingLastPathComponent ],
                        newstring ];
        
        if ( rename( [[ dict objectForKey: @"name" ] UTF8String ],
                        [ newpath UTF8String ] ) < 0 ) {
            NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
                NSLocalizedString( @"rename %@ to %@: %s", @"rename %@ to %@: %s" ),
                NSLocalizedString( @"OK", @"OK" ), @"", @"",
                [ dict objectForKey: @"name" ],
                newpath, strerror( errno ));
            return( NO );
        }
        dict = [[ SFTPNode sharedInstance ]
                    statInformationForPath: newpath ];
        [ items replaceObjectAtIndex: row withObject: dict ];
    } else if ( [ table isEqual: remoteBrowser ] ) {
        char		renamecmd[ MAXPATHLEN ];
        
        if ( ! [ newstring length ] ) return( NO );
        
        items = ( dotflag ? remoteDirContents : dotlessRDir );
        
        if ( snprintf( renamecmd, MAXPATHLEN, "rename \"%s\" \"%s\"",
                [[[ items objectAtIndex: row ] objectForKey: @"name" ] UTF8String ],
                [ newstring UTF8String ] ) > ( MAXPATHLEN - 1 )) {
            NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
                @"snprintf string exceeds bounds.", NSLocalizedString( @"OK", @"OK" ),
                @"", @"" );
            return( NO );
        }
        [ self writeCommand: renamecmd ];
    }
        
    return( YES );
}

- ( BOOL )handleEvent: ( NSEvent * )theEvent fromTable: ( SFTPTableView * )table
{
    unichar 		key = [[ theEvent charactersIgnoringModifiers ] characterAtIndex: 0 ];
    
    if ( key == NSDeleteCharacter ) {
        [ self delete: nil ];
        return( YES );
    } else if ( key == NSRightArrowFunctionKey ) {
        [ self changeDirectory: nil ];
        return( YES );
    } else if ( key == NSLeftArrowFunctionKey ) {
        [ self dotdot: nil ];
        return( YES );
    } else if ( key == NSEnterCharacter ) {
        if ( [ table isEqual: localBrowser ] ) {
            [ self renameLocalItem: nil ];
        } else if ( [ table isEqual: remoteBrowser ] ) {
            [ self renameRemoteItem: nil ];
        }
        return( YES );
    } else if ( key == NSF8FunctionKey ) {
        int		row = [ table selectedRow ];
        NSMenu		*menu = nil;
        NSEvent		*e = nil;
        NSRect		rect; 
        NSPoint		p;
        
        if ( row < 0 ) {
            return( NO );
        }
        
        rect = [ table frameOfCellAtColumn: 0
                        row: [ table selectedRow ]];
        p = NSMakePoint( rect.origin.x, rect.origin.y );
        p = [[[ table window ] contentView ] convertPoint: p fromView: table ];
        
        if ( [ table isFlipped ] ) {
            p.x += 15.0;
            p.y -= 15.0;
        } else {
            p.x -= 15.0;
            p.y += 15.0;
        }
        
        if ( [ table isEqual: localBrowser ] ) {
            menu = localTableMenu;
        } else if ( [ table isEqual: remoteBrowser ] ) {
            menu = remoteTableMenu;
        }
        e = [ NSEvent mouseEventWithType: NSRightMouseUp location: p
                        modifierFlags: 0 timestamp: 1
                        windowNumber: [[ table window ] windowNumber ]
                        context: [ NSGraphicsContext currentContext ]
                        eventNumber: 1 clickCount: 1 pressure: 0.0 ];
                    
        [ NSMenu popUpContextMenu: menu withEvent: e forView: nil ];
        return( YES );
    } else if ( isascii( key )) {
        int		row;
        
        [ NSObject cancelPreviousPerformRequestsWithTarget: self
                    selector: @selector( clearTypeAheadString )
                    object: nil ];
        [ self performSelector: @selector( clearTypeAheadString )
                withObject: nil
                afterDelay: 0.5 ];
        if ( typeAheadString == nil ) {
            typeAheadString = [[ NSMutableString alloc ] init ];
            [ typeAheadString setString: @"" ];
        }
        [ typeAheadString appendString: [ NSString stringWithFormat: @"%c", key ]];
        row = [ self matchingIndexForString: typeAheadString inTable: table ];
        
        if ( row < 0 ) return( NO );
        [ table scrollRowToVisible: row ];
        [ table selectRow: row byExtendingSelection: NO ];
        return( YES );
    }
        
    return( NO );
}

- ( void )clearTypeAheadString
{
    if ( typeAheadString != nil ) {
        [ typeAheadString release ];
    }
    typeAheadString = nil;
}

- ( int )matchingIndexForString: ( NSString * )string inTable: ( SFTPTableView * )table
{
    NSMutableArray		*items;
    NSDictionary		*dict;
    int				index = -1, i;
    
    if ( string == nil ) return( -1 );
    
    if ( [ table isEqual: localBrowser ] ) {
        items = ( dotflag ? localDirContents : dotlessLDir );
        for ( i = 0; i < [ items count ]; i++ ) {
            dict = [ items objectAtIndex: i ];
            if ( [[[ dict objectForKey: @"name" ]
                        lastPathComponent ] beginsWithString: string ] ) {
                index = i;
                break;
            }
        }
    } else if ( [ table isEqual: remoteBrowser ] && connected ) {
        items = ( dotflag ? remoteDirContents : dotlessRDir );
        for ( i = 0; i < [ items count ]; i++ ) {
            dict = [ items objectAtIndex: i ];
            if ( [[ dict objectForKey: @"name" ] beginsWithString: string ] ) {
                index = i;
                break;
            }
        }
    }
    return( index );
}

- ( NSArray * )editedDocuments
{
    return(( NSArray * )editedDocuments );
}

- ( void )addToEditedDocuments: ( NSString * )docpath remotePath: ( NSString * )rpath
{
    NSString			*user = [ userName stringValue ];
    NSString			*host = [ remoteHost stringValue ];
    
    if ( editedDocuments == nil ) {
	editedDocuments = [[ NSMutableArray alloc ] init ];
    }
    
    if ( [ user isEqualToString: @"" ] ) {
	user = @"N/A";
    }
    if ( [ host isEqualToString: @"" ] ) {
	host = @"N/A";
    }

    [ editedDocuments addObject: [ NSDictionary dictionaryWithObjectsAndKeys:
		    docpath, @"localpath",
		    rpath, @"remotepath",
		    user, @"username",
		    host, @"hostname", nil ]];
}

- ( void )removeFromEditedDocuments: ( NSString * )docpath
{
    unsigned int		i;
    
    for ( i = 0; i < [ editedDocuments count ]; i++ ) {
	NSDictionary		*dict = [ editedDocuments objectAtIndex: i ];
	NSString		*localpath = [ dict objectForKey: @"localpath" ];
	
	if ( [ localpath isEqualToString: docpath ] ) {
	    if ( unlink( [ localpath UTF8String ] ) < 0 ) {
		if ( errno != ENOENT ) {
		    NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
			@"unlink %@: %s", NSLocalizedString( @"OK", @"OK" ), @"", @"",
			localpath, strerror( errno ));
		    return;
		}
	    }
	    if ( rmdir( [[ localpath stringByDeletingLastPathComponent ] UTF8String ] ) < 0 ) {
		if ( errno != ENOENT ) {
		    NSRunAlertPanel( NSLocalizedString( @"Error", @"Error" ),
			@"unlink %@: %s", NSLocalizedString( @"OK", @"OK" ), @"", @"",
			localpath, strerror( errno ));
		    return;
		}
	    }
		
	    [ editedDocuments removeObjectAtIndex: i ];
	    break;
	}
    }
}

- ( void )setPreviewedImage: ( NSString * )imagepath
{
    if ( previewedImage != nil ) {
        [ previewedImage release ];
        previewedImage = nil;
    }
    
    if ( imagepath == nil ) {
        return;
    }
    
    previewedImage = [[ NSString alloc ] initWithString: imagepath ];
}

- ( NSString * )previewedImage
{
    return( previewedImage );
}

- ( void )addToCachedPreviews: ( NSDictionary *)cachedData
{
    if ( cachedPreviews == nil ) {
        cachedPreviews = [[ NSMutableArray alloc ] init ];
    }
    [ cachedPreviews addObject: cachedData ];
}

- ( NSArray * )cachedPreviews
{
    return( cachedPreviews );
}

- ( IBAction )selectRendezvousServer: ( id )sender
{
    [ remoteHost setStringValue: [ rendezvousPopUp titleOfSelectedItem ]];
}

- ( void )scanForSSHServers: ( id )sender
{
    /* find rendezvous-enabled ssh servers, populate list with them */
    if ( sshServiceBrowser == nil ) {
	sshServiceBrowser = [[ NSNetServiceBrowser alloc ] init ];
    }
    
    [ sshServiceBrowser setDelegate: self ];
    [ sshServiceBrowser searchForServicesOfType: @"_ssh._tcp" inDomain: @"" ];
}

/* NSNetService delegate method */
- ( void )netServiceDidResolveAddress: ( NSNetService * )sender
{
    NSData		*address;
    NSString		*serviceAddress = nil;
    struct sockaddr_in  *ip;
    struct hostent	*he;
    char                *service_address;
    unsigned int        port;

    if ( [[ sender addresses ] count ] <= 0 ) {
	return;
    }
    
    address = [[ sender addresses ] objectAtIndex: 0 ];
    
    if ((( struct sockaddr * )[ address bytes ] )->sa_family != AF_INET &&
			(( struct sockaddr * )[ address bytes ] )->sa_family != AF_INET6 ) {
        NSLog( @"%d: unknown address family.\n",
                        (( struct sockaddr * )[ address bytes ] )->sa_family );
    }

    ip = ( struct sockaddr_in * )[ address bytes ];
    if (( service_address = strdup( inet_ntoa( ip->sin_addr ))) == NULL ) {
        perror( "strdup" );
        exit( 2 );
    }

    port = ntohs( ip->sin_port );

    if (( he = gethostbyaddr(( char * )&ip->sin_addr,
                                sizeof( struct in_addr ), AF_INET )) == NULL ) {
        serviceAddress = [ NSString stringWithUTF8String: service_address ];
    } else {
        serviceAddress = [ NSString stringWithUTF8String: he->h_name ];
    }
    
    if ( ! [[ rendezvousPopUp itemTitles ] containsObject: serviceAddress ] &&
	    ! [ serviceAddress isEqualToString: @"" ] ) {
	[ rendezvousPopUp addItemWithTitle: serviceAddress ];
    }

    free( service_address );
}

- ( void )netServiceBrowser: ( NSNetServiceBrowser * )aNetServiceBrowser
            didFindService: ( NSNetService * )netService
            moreComing: ( BOOL )moreComing
{
    if ( services == nil ) {
        services = [[ NSMutableArray alloc ] init ];
    }
    [ services addObject: netService ];
    
    if ( ! moreComing ) {
        int		i;
        
        for ( i = 0; i < [ services count ]; i++ ) {
            [[ services objectAtIndex: i ] setDelegate: self ];
	    if ( [[ services objectAtIndex: i ]
			    respondsToSelector: @selector( resolveWithTimeout: ) ] ) {
		    [[ services objectAtIndex: i ] resolveWithTimeout: 5 ];
	    } else {
		    [[ services objectAtIndex: i ] resolve ];
	    }
        }
        
        [ rendezvousPopUp setEnabled: YES ];
    }
}

- ( void )netServiceBrowser: ( NSNetServiceBrowser * )aNetServiceBrowser
        didRemoveService: ( NSNetService * )netService
        moreComing: ( BOOL )moreComing
{
    int			i;
    
    if ( services == nil ) {
	return;
    }
    
    for ( i = 0; i < [ services count ]; i++ ) {
        if ( [[ services objectAtIndex: i ] isEqual: netService ] ) {
            [ services removeObjectAtIndex: i ];
            break;
        }
    }
    
    if ( ! moreComing ) {
        int		i;

	[ rendezvousPopUp removeAllItems ];
        [ rendezvousPopUp addItemWithTitle: @"" ];
	[[ rendezvousPopUp itemAtIndex: 0 ] setImage: [ NSImage imageNamed: @"zeroconf.png" ]];
	
        for ( i = 0; i < [ services count ]; i++ ) {
            [[ services objectAtIndex: i ] setDelegate: self ];
            [[ services objectAtIndex: i ] resolve ];
        }
        
        if ( [ services count ] == 0 ) {
            [ rendezvousPopUp setEnabled: NO ];
        }
    }
}

/* splitview delegate methods */
- ( float )splitView: ( NSSplitView * )splitview constrainMaxCoordinate: ( float )proposedMax
            ofSubviewAt: ( int )offset
{
    return(( proposedMax - 175 ));
}

- ( float )splitView: ( NSSplitView * )splitview constrainMinCoordinate: ( float )proposedMax
            ofSubviewAt: ( int )offset
{
    return(( proposedMax + 175 ));
}

/* tabview delegate methods */
- ( BOOL )tabView: ( NSTabView * )tabView shouldSelectTabViewItem: ( NSTabViewItem * )tabViewItem
{
    /* don't allow user to select remote info tab if not connected */
    if ( ! connected && [[ tabViewItem identifier ] isEqualToString: @"remote" ] ) {
        return( NO );
    }
    return( YES );
}

/*
 * sftptable dataSource: returns array of names
 */
- ( NSArray * )promisedNamesFromPlists: ( id )plists
{
    NSMutableArray	    *a = nil;
    NSArray		    *promisedNames = nil;
    NSAutoreleasePool	    *pool;
    NSString		    *name;
    id			    plist;
    int			    i;
    
    if ( ! [ plists isKindOfClass: [ NSArray class ]] ) {
	NSLog( @"%@: unsupported data class", [ plist class ] );
	return( nil );
    }
    if ( [ plists count ] == 0 ) {
	NSLog( @"%@: no contents", plist );
	return( nil );
    }
    
    plist = [ plists objectAtIndex: 0 ];

    pool = [[ NSAutoreleasePool alloc ] init ];
    a = [[ NSMutableArray alloc ] initWithCapacity: [ plist count ]];
    for ( i = 0; i < [ plist count ]; i++ ) {
	name = [[ plist objectAtIndex: i ] objectForKey: @"name" ];
	if ( name == nil ) {
	    continue;
	}
	
	[ a addObject: name ];
    }
    [ pool release ];
    
    if ( [ a count ] ) {
	promisedNames = [ NSArray arrayWithArray: a ];
    }
    [ a release ];
    
    return( promisedNames );
}

- ( BOOL )handleDroppedPromisedFiles: ( NSArray * )promisedFiles
	    destination: ( NSString * )dropDestination
{
    if ( promisedFiles == nil || [ promisedFiles count ] == 0 ) {
	return( NO );
    }
    
    [ self downloadFiles: promisedFiles toDirectory: dropDestination ];
    
    return( YES );
}

/* tableview delegate methods */
/* contextual menu for tables */
- ( NSMenu * )menuForTable: ( SFTPTableView * )table
                column: ( int )column row: ( int )row
{
    if ( [ table isEqual: localBrowser ] ) {
        return( localTableMenu );
    } else if ( [ table isEqual: remoteBrowser ] ) {
        return( remoteTableMenu );
    }
    return( nil );
}

- ( void )tableViewSelectionDidChange: ( NSNotification * )aNotification
{
    id 				tv = [ aNotification object ];
    int				numselected;
    
    if ( ! [ tv isKindOfClass: [ SFTPTableView class ]] ) {
        return;
    }
    
    numselected = [ tv numberOfSelectedRows ];
    
    if ( [ tv editedRow ] >= 0 ) {
        [ tv abortEditing ];
    }
    
    if ( [ infoPanel isVisible ] && numselected == 1 ) {
        [ self getInfo: nil ];
    }
    
    if ( [ imagePreviewPanel isVisible ] && numselected == 1 ) {
        [ self previewItem: nil ];
    }
}

- ( void )tableView: ( NSTableView * )table
        didClickTableColumn: ( NSTableColumn * )tableColumn
{
    NSArray		*columns = [ table tableColumns ];
    int			i, sortdirection;
    int			( *sortFunction )( id, id, void * );
    unsigned		context;
    id			identifier;
    NSImage		*image = nil;
    
    image = [ table indicatorImageInTableColumn: tableColumn ];
    if ( [ image isEqual:
            [ NSImage imageNamed: @"NSAscendingSortIndicator" ]] ) {
        image = [ NSImage imageNamed: @"NSDescendingSortIndicator" ];
        sortdirection = 1;
    } else {
        image = [ NSImage imageNamed: @"NSAscendingSortIndicator" ];
        sortdirection = 0;
    }
    [ image retain ];
    
    for ( i = 0; i < [ columns count ]; i++ ) {
        [ table setIndicatorImage: nil
                inTableColumn: [ columns objectAtIndex: i ]];
    }
            
    identifier = [ tableColumn identifier ];
    
    sortFunction = sortFunctionForIdentifier( identifier );
    
    if ( [[ NSUserDefaults standardUserDefaults ]
            boolForKey: @"ASCIIOrderSorting" ] ) {
        context = NSLiteralSearch;
    } else {
        context = NSCaseInsensitiveSearch;
    }
    
    if ( [ table isEqual: localBrowser ] ) {
        if ( [[[ table highlightedTableColumn ] identifier ]
                        isEqualToString: identifier ] ) {
            [ localDirContents reverse ];
        } else {
            [ localDirContents sortUsingFunction: sortFunction
                            context: ( void * )&context ];
        }
        [ dotlessLDir removeAllObjects ];
        [ dotlessLDir addObjectsFromArray: [ localDirContents visibleItems ]];
        [[ NSUserDefaults standardUserDefaults ] setObject: identifier
                                forKey: @"LocalBrowserSortingIdentifier" ];
        [[ NSUserDefaults standardUserDefaults ] setObject:
            [ NSNumber numberWithInt: sortdirection ]
                            forKey: @"LocalBrowserSortDirection" ];
    } else if ( [ table isEqual: remoteBrowser ] ) {
        if ( [[[ table highlightedTableColumn ] identifier ]
                        isEqualToString: identifier ] ) {
            [ remoteDirContents reverse ];
        } else {
            [ remoteDirContents sortUsingFunction: sortFunction
                            context: ( void * )&context ];
        }
        [ dotlessRDir removeAllObjects ];
        [ dotlessRDir addObjectsFromArray: [ remoteDirContents visibleItems ]];
        [[ NSUserDefaults standardUserDefaults ] setObject: identifier
                                forKey: @"RemoteBrowserSortingIdentifier" ];
        [[ NSUserDefaults standardUserDefaults ] setObject:
            [ NSNumber numberWithInt: sortdirection ]
                            forKey: @"RemoteBrowserSortDirection" ];
    }
    
    [ table setHighlightedTableColumn: tableColumn ];
    [ table setIndicatorImage: image
            inTableColumn: tableColumn ];
    [ image release ];
    [ table reloadData ];
}

- ( BOOL )tableView: ( NSTableView * )aTableView
        shouldEditTableColumn: ( NSTableColumn * )aTableColumn
        row: ( int )rowIndex
{
    /* if user's chosen to rename a file, allow editing */
    if ( [ aTableView editedRow ] >= 0 ) return( YES );
    
    return( NO );	/* so doubleclicks register as such */
}
            

- ( int )numberOfRowsInTableView: ( NSTableView * )aTableView
{
    NSMutableArray	*items = nil;
    
    if ( [ aTableView isEqual: localBrowser ] ) {
        if ( !dotflag ) {
            items = dotlessLDir;
        } else {
            items = localDirContents;
        }
    } else if ( [ aTableView isEqual: remoteBrowser ] ) {
        if ( !dotflag ) {
            items = dotlessRDir;
        } else {
            items = remoteDirContents;
        }
    }
    
    return( [ items count ] );
}

- ( id )tableView: ( NSTableView * )view
        objectValueForTableColumn: ( NSTableColumn * )aTableColumn
        row: ( int )row
{
    NSString			*path = nil, *ext = nil;
    NSAttributedString          *attrString = nil;
    NSImage			*image = nil;
    int				therow = row;
    NSString			*name = nil;
    id				cell = [ aTableColumn dataCell ];
    double                      width = [ aTableColumn width ];
    
    if ( row < 0 ) {
        return( nil );
    }

    if ( view == localBrowser ) {
        NSDictionary		*dict;
        NSString		*resolvedpath;
        
        if ( !dotflag ) {
            dict = [ dotlessLDir objectAtIndex: therow ];
        } else {
            dict = [ localDirContents objectAtIndex: therow ];
        }

        resolvedpath = [ dict objectForKey: @"resolvedAlias" ];
        
        if ( [[ aTableColumn identifier ] isEqualToString: @"namecolumn" ] ) {
            path = [ dict objectForKey: @"name" ];
            ext = [ path pathExtension ];

            if ( access(( char * )[ path UTF8String ], F_OK ) == 0 &&
                        resolvedpath == nil ) {
                /* display name at path shows resolved symlink names */
                name = [[ NSFileManager defaultManager ] displayNameAtPath: path ];
            } else {
                name = [ path lastPathComponent ];
            }
            
            image = [ dict objectForKey: @"icon" ];
            
            [ cell setImage: image ];
            [ cell setEditable: YES ];
            attrString = [[[ NSAttributedString alloc ] initWithString: name ] autorelease ];
            
            attrString = [ attrString ellipsisAbbreviatedStringForWidth: width ];
            
            return( attrString );
        } else if ( [[ aTableColumn identifier ] isEqualToString: @"datecolumn" ] ) {
            NSString		*date = [ dict objectForKey: @"date" ];
            
            if ( date != nil ) {
                return( date );
            }
        } else if ( [[ aTableColumn identifier ] isEqualToString: @"sizecolumn" ] ) {
            NSString		*size = [ dict objectForKey: @"size" ];
            
            if ( size != nil ) {
                return( [ size descriptiveSizeString ] );
            }
        } else if ( [[ aTableColumn identifier ] isEqualToString: @"ownercolumn" ] ) {
            NSString		*owner = [ dict objectForKey: @"owner" ];
            
            if ( owner != nil ) {
                return( owner );
            }
        } else if ( [[ aTableColumn identifier ] isEqualToString: @"groupcolumn" ] ) {
            NSString		*group = [ dict objectForKey: @"group" ];
            
            if ( group != nil ) {
                return( group );
            }
        } else if ( [[ aTableColumn identifier ] isEqualToString: @"permcolumn" ] ) {
            NSString		*mode = [ dict objectForKey: @"perm" ];
            
            if ( mode != nil ) {
                return( [ mode stringRepresentationOfOctalMode ] );
            }
        }
    } else if ( [ view isEqual: remoteBrowser ] ) {
        NSDictionary		*dict;
        
        if ( !dotflag ) {
            dict = [ dotlessRDir objectAtIndex: therow ];
        } else {
            dict = [ remoteDirContents objectAtIndex: therow ];
        }

        if ( [[ aTableColumn identifier ] isEqualToString: @"namecolumn" ] ) {
            name = [[ dict objectForKey: @"name" ] lastPathComponent ];
            ext = [ name pathExtension ];
        
            switch ( [[ dict objectForKey: @"perm" ] characterAtIndex: 0 ] ) {
            case '-':
            default:
                if ( [ ext isEqualToString: @"" ] ) {
                    image = fileImage;
                } else {
                    image = [ NSImage iconForType: ext ];
                    [ image setSize: NSMakeSize( 16.0, 16.0 ) ];
                }
                break;
                
            case 'd':
                image = dirImage;
                break;
                
            case 'l':
                //[ cell italicizeStringValue ];
                image = linkImage;
                break;
            }
            
            [ cell setImage: image ];
            [ cell setEditable: YES ];
            
            attrString = [[[ NSAttributedString alloc ] initWithString: name ] autorelease ];
            attrString = [ attrString ellipsisAbbreviatedStringForWidth: width ];
            
            return( attrString );
        } else if ( [[ aTableColumn identifier ] isEqualToString: @"sizecolumn" ] ) {
            NSString		*size = [ dict objectForKey: @"size" ];
            
            if ( size != nil ) {
                return( [ size descriptiveSizeString ] );
            }
        } else if ( [[ aTableColumn identifier ] isEqualToString: @"ownercolumn" ] ) {
            NSString		*owner = [ dict objectForKey: @"owner" ];
            
            if ( owner == nil ) {
                owner = @"";
            }
            [ cell setEditable: NO ];
            return( owner );
        } else if ( [[ aTableColumn identifier ] isEqualToString: @"datecolumn" ] ) {
            NSString		*date = [ dict objectForKey: @"date" ];
            
            if ( date == nil ) {
                date = @"";
            }
            [ cell setEditable: NO ];
            return( date );
        } else if ( [[ aTableColumn identifier ] isEqualToString: @"groupcolumn" ] ) {
            NSString		*group = [ dict objectForKey: @"group" ];
            
            if ( group != nil ) {
                return( group );
            }
        } else if ( [[ aTableColumn identifier ] isEqualToString: @"permcolumn" ] ) {
            NSString		*mode = [ dict objectForKey: @"perm" ];
            
            if ( mode != nil ) {
                return( mode );
            }
        }
    }
    
    [ cell setEditable: NO ];
    return( @"" );
}

- ( void )tableView: ( NSTableView * )aTableView
        setObjectValue: ( id )anObject
        forTableColumn: ( NSTableColumn * )aTableColumn
        row: ( int )rowIndex
{
}

/* drag and drop related methods */

- ( BOOL )tableView: ( NSTableView * )tableView acceptDrop: ( id <NSDraggingInfo> )info
    row: ( int )row dropOperation: ( NSTableViewDropOperation )operation
{
    NSPasteboard		*pb;
    id				dragData;

    pb = [ info draggingPasteboard ];
    
    /* clear spring-loaded root path */
    if ( _springLoadedRootPath != nil ) {
        [ _springLoadedRootPath release ];
        _springLoadedRootPath = nil;
    }
    
    if ( tableView == localBrowser ) {
        NSString		*lpath = localDirPath;
        
        if ( operation == NSTableViewDropOn && row >= 0 ) {
            lpath = [[ ( dotflag ? localDirContents : dotlessLDir )
                        objectAtIndex: row ] objectForKey: @"name" ];
        }
        dragData = [ pb propertyListForType:
                [ pb availableTypeFromArray:
                    [ NSArray arrayWithObject: NSFileContentsPboardType ]]];
                    
        if ( [ dragData count ] == 1 &&
                [[[ dragData objectAtIndex: 0 ] objectForKey: @"type" ]
                isEqualToString: @"directory" ] ) {
            int			rc;

            rc = NSRunAlertPanel(
                NSLocalizedString( @"Warning: OpenSSH's sftp client cannot yet download directories.",
                                @"Warning: OpenSSH's sftp client cannot yet download directories." ),
                NSLocalizedString( @"Would you like to download %@ to %@ with SCP instead?",
                                @"Would you like to download %@ to %@ with SCP instead?" ),
                NSLocalizedString( @"Download", @"Download" ),
                NSLocalizedString( @"Cancel", @"Cancel" ), @"",
                [[ dragData objectAtIndex: 0 ] objectForKey: @"name" ], lpath );
            switch ( rc ) {
            case NSAlertDefaultReturn:
                [ self scpRemoteItem:
                        [[ dragData objectAtIndex: 0 ] objectForKey: @"name" ]
                        fromHost: [ remoteHost stringValue ]
                        toLocalPath: lpath userName: [ userName stringValue ]];
            case NSAlertAlternateReturn:
            default:
                return( YES );
            }
        }

        [ self downloadFiles: dragData toDirectory: lpath ];
        return( YES );
    } else if ( tableView == remoteBrowser ) {
        NSString		*rpath = @".";
        
        if ( !connected ) return( NO );
        if ( operation == NSTableViewDropOn && row >= 0 ) {
            rpath = [[ ( dotflag ? remoteDirContents : dotlessRDir ) objectAtIndex: row ]
                                                                        objectForKey: @"name" ];
        }

        dragData = [ pb propertyListForType:
                [ pb availableTypeFromArray:
                    [ NSArray arrayWithObject: NSFilenamesPboardType ]]];
        
        [ self uploadFiles: dragData toDirectory: rpath ];        
        return( YES );
    }
    
    return( NO );
}

- ( NSDragOperation )tableView: ( NSTableView * )tableView validateDrop:( id <NSDraggingInfo> )info
    proposedRow: ( int )row proposedDropOperation: ( NSTableViewDropOperation )operation
{
    id			dsrc;
    
    if ( operation == NSTableViewDropOn && row == -1 ) {
        return( NSDragOperationCopy );
    } else if ( operation == NSTableViewDropAbove ) {
        [ tableView setDropRow: -1 dropOperation: NSTableViewDropOn ];
        return( NSDragOperationCopy );
    } else if ( operation == NSTableViewDropOn && row >= 0 ) {
        if ( tableView == remoteBrowser ) {
            if ( dotflag ) dsrc = [ remoteDirContents copy ];
            else dsrc = [ dotlessRDir copy ];
            
            if ( [[[ dsrc objectAtIndex: row ]
                    objectForKey: @"perm" ] characterAtIndex: 0 ] == 'd' ) {
                [ dsrc release ];
                return( NSDragOperationCopy );
            }
            [ dsrc release ];
        } else {
            BOOL	isDir;
            
            if ( dotflag ) dsrc = [ localDirContents copy ];
            else dsrc = [ dotlessLDir copy ];
            
            if ( [[ NSFileManager defaultManager ] fileExistsAtPath:
                    [[ dsrc objectAtIndex: row ] objectForKey: @"name" ]
                    isDirectory: &isDir ] && isDir ) {
                [ dsrc release ];
                return( NSDragOperationCopy );
            }
            [ dsrc release ];
        }
    }

    return( NSDragOperationNone );
}

- ( BOOL )tableView: ( NSTableView * )tableView writeRows: ( NSArray * )rows
    toPasteboard: ( NSPasteboard * )pboard
{
    id			dsrc = nil;
    int 		i;
    NSArray 		*anArray = [ NSArray array ];
    NSString		*path;
    
    if ( ! connected ) return( NO );
    
    if ( tableView == localBrowser ) {
        if ( !dotflag ) {
            dsrc = [ dotlessLDir copy ];
        } else {
            dsrc = [ localDirContents copy ];
        }
        
        for ( i = 0; i < [ rows count ]; i++ ) {
            path = [[ dsrc objectAtIndex: [[ rows objectAtIndex: i ] intValue ]]
                            objectForKey: @"name" ];
            anArray = [ anArray arrayByAddingObject: path ];
        }
        [ pboard declareTypes: [ NSArray arrayWithObject: NSFilenamesPboardType ] owner: self ];
        [ pboard setPropertyList: anArray forType: NSFilenamesPboardType ];
    } else if ( tableView == remoteBrowser ) {
#ifdef notdef
        NSRect		imageLocation = [ remoteBrowser frameOfCellAtColumn: 0
                                            row: [[ rows objectAtIndex: 0 ] intValue ]];
#endif notdef
        
        if ( !dotflag ) {
            dsrc = [ dotlessRDir copy ];
        } else {
            dsrc = [ remoteDirContents copy ];
        }
        
        for ( i = 0; i < [ rows count ]; i++ ) {
            anArray = [ anArray arrayByAddingObject:
                    [ dsrc objectAtIndex: [[ rows objectAtIndex: i ] intValue ]]];
        }
        [ pboard declareTypes: [ NSArray arrayWithObject: NSFileContentsPboardType ]
                    owner: self ];
        [ pboard setPropertyList: anArray forType: NSFileContentsPboardType ];
	[ remoteBrowser setDragPromisedFiles: YES ];
#ifdef notdef
        [ remoteBrowser dragPromisedFilesOfTypes: [ NSArray arrayWithObject: @"'docs'" ]
		    fromRect: imageLocation source: remoteBrowser slideBack: YES
                    event: [[ remoteBrowser window ] currentEvent ]];
        return( NO );
#endif notdef
    }
    
    [ dsrc release ];
    
    return( YES );
}

- ( IBAction )showPrefs: ( id )sender
{
    if ( prefs == nil ) {
        prefs = [[ SFTPPrefs alloc ] init ];
        [ NSBundle loadNibNamed: @"Prefs.nib" owner: prefs ];
    }
    [ prefs showPreferencePanel ];
}

- ( void )dealloc
{
    if ( prefs != nil ) {
        [ prefs release ];
    }
    [ dirImage release ];
    [ fileImage release ];
    [ remoteDirBuf release ];
    [ uploadQueue release ];
    [ remoteDirContents release ];
    [ dotlessRDir release ];
    [ dotlessLDir release ];
    [ remoteDirPath release ];
    [ userParameters release ];
    [ rSwitchArray release ];
    
    if ( sshServiceBrowser != nil ) {
	[ sshServiceBrowser release ];
    }
    
    if ( services != nil ) {
	[ services release ];
    }
    
    if ( scp != nil ) {
        [ scp release ];
    }
    
    [ super dealloc ];
}

- ( void )applicationDidFinishLaunching: ( NSNotification * )aNotification
{
    [ NSApp setServicesProvider: self ];
    [[ remoteHost window ] makeFirstResponder: remoteHost ];
}

- ( BOOL )application: ( NSApplication * )theApplication
	    openFile: ( NSString * )aFileName
{
    if ( scp == nil ) {
        scp = [[ SCPController alloc ] init ];
        [ NSBundle loadNibNamed: @"SCP" owner: scp ];
    }
    
    [ scp getSecureCopyWindowForFile: aFileName scpType: 0 copyToPath: @""
                fromHost: @"" userName: @"" delegate: self ];
                
    return( YES );
}

- ( void )applicationWillTerminate: ( NSNotification * )aNotification
{
    int			i;
    NSArray		*array;
    NSMutableArray	*columnArray = nil;
    
    if ( access( C_TMPFUGUDIR, F_OK | W_OK ) == 0 ) {
        if ( [[ NSFileManager defaultManager ]
                removeFileAtPath: OBJC_TMPFUGUDIR handler: nil ] == NO ) {
            NSLog( @"Couldn't remove %@!", OBJC_TMPFUGUDIR );
        }
    }
    
    /* save column settings */
    array = [ localBrowser tableColumns ];
    columnArray = [[ NSMutableArray alloc ] init ];
                
    for ( i = 1; i < [ array count ]; i++ ) {
        NSString	*identifier = [[ array objectAtIndex: i ] identifier ];
        float		width = [[ array objectAtIndex: i ] width ];
        
        [ columnArray addObject: [ NSDictionary dictionaryWithObjectsAndKeys:
                        identifier, @"identifier",
                        [ NSNumber numberWithFloat: width ], @"width", nil ]];
    }
    
    [[ NSUserDefaults standardUserDefaults ] setObject: columnArray
                                            forKey: @"VisibleColumns" ];
    [ columnArray release ];
}

- ( IBAction )checkForUpdates: ( id )sender
{
    UMVersionCheck      *check = [[ UMVersionCheck alloc ] init ];
    
    [ check checkForUpdates ];
    [ check release ];
}

- ( IBAction )newSSHTunnel: ( id )sender
{
    SSHTunnel		*t = [[ SSHTunnel alloc ] init ];
    
    [ NSBundle loadNibNamed: @"SSHTunnel" owner: t ];
    [ t displayWindow ];
    [ t autorelease ];
}

- ( IBAction )secureCopy: ( id )sender
{
    if ( scp == nil ) {
        scp = [[ SCPController alloc ] init ];
        [ NSBundle loadNibNamed: @"SCP" owner: scp ];
    }
    
    [ scp getSecureCopyWindowForFile: @"" scpType: 0 copyToPath: @"" fromHost: @"" userName: @"" 
            delegate: self ];
}

/* download files/directories with scp */
- ( IBAction )scp: ( id )sender
{
    int			row;
    id			item;
    
    if ( [ sender isKindOfClass: [ NSMenuItem class ]] ) {
        /* check to make sure we've got something valid */
        NSString	*user = [ userName stringValue ], *host = [ remoteHost stringValue ];
        if ( ! [ user length ] ) user = NSUserName();
        if ( ! [ host length ] ) host = @"127.0.0.1";

        if ( [[ sender menu ] isEqual: localTableMenu ] ) {
            
            row = [ localBrowser selectedRow ];
            if ( row < 0 ) return;
            
            if ( dotflag ) {
                item = [[ localDirContents objectAtIndex: row ]
                                objectForKey: @"name" ];
            } else {
                item = [[ dotlessLDir objectAtIndex: row ]
                                objectForKey: @"name" ];
            }
            
            
            [ self scpLocalItem: item
                    toHost: host
                    userName: user ];
        } else if ( [[ sender menu ] isEqual: remoteTableMenu ] ) {
            row = [ remoteBrowser selectedRow ];
            if ( row < 0 ) return;
            
            if ( dotflag ) {
                item = [[ remoteDirContents objectAtIndex: row ]
                                objectForKey: @"name" ];
            } else {
                item = [[ dotlessRDir objectAtIndex: row ] objectForKey: @"name" ];
            }
            
            [ self scpRemoteItem: item
                    fromHost: host
                    toLocalPath: localDirPath
                    userName: user ];
        }
    }
}

- ( void )scpRemoteItem: ( NSString * )rdir fromHost: ( NSString * )rhost
        toLocalPath: ( NSString * )ldir userName: ( NSString * )user
{
    NSString		*fullRemoteDirPath = [ NSString stringWithFormat: @"%@/%@",
                                                remoteDirPath, rdir ];
                                                
    if ( scp == nil ) {
        scp = [[ SCPController alloc ] init ];
        [ NSBundle loadNibNamed: @"SCP" owner: scp ];
    }

    [ scp getSecureCopyWindowForFile: fullRemoteDirPath scpType: 1
            copyToPath: ldir fromHost: rhost userName: user delegate: self ];
}

- ( void )scpLocalItem: ( NSString * )item toHost: ( NSString * )rhost
        userName: ( NSString * )user
{
    NSString		*dir = remoteDirPath;
                                            
    if ( dir == nil ) dir = @" ";
    
    if ( scp == nil ) {
        scp = [[ SCPController alloc ] init ];
        [ NSBundle loadNibNamed: @"SCP" owner: scp ];
    }
    
    [ scp getSecureCopyWindowForFile: item scpType: 0
            copyToPath: dir fromHost: rhost userName: user delegate: self ];
}

/* SCPController delegate method, called when an scp completes */
- ( void )scpFinished
{
    if ( [ mainWindow isVisible ] && localDirPath != nil ) {
        [ self localBrowserReloadForPath: localDirPath ];
    }
}

/* provide scp service */
- ( void )secureCopyFile: ( NSPasteboard * )pboard
            userData: ( NSString * )userData
            error: ( NSString ** )error
{
    NSArray		*filenames;
    NSArray		*types = [ pboard types ];
    
    if ( ![ types containsObject: NSFilenamesPboardType ] ) {
        *error = @"Pasteboard doesn't contain any filenames";
        return;
    }
    filenames = [ pboard propertyListForType:
                    [ pboard availableTypeFromArray:
                            [ NSArray arrayWithObject: NSFilenamesPboardType ]]];
    if ( filenames == nil ) {
        *error = @"Couldn't extract filename from pasteboard.";
        return;
    }
    scp_service = 1;
    
    if ( scp == nil ) {
        scp = [[ SCPController alloc ] init ];
        [ NSBundle loadNibNamed: @"SCP" owner: scp ];
    }

    [ scp getSecureCopyWindowForFile: [ filenames objectAtIndex: 0 ] 
        scpType: 0 copyToPath: @"" fromHost: @"" userName: @"" delegate: self ];
}

/* provide ssh tunnel service */
- ( void )createSSHTunnel: ( NSPasteboard * )pboard
            userData: ( NSString * )userData
            error: ( NSString ** )error
{
    SSHTunnel		*ssht = [[ SSHTunnel alloc ] init ];
    
    [ NSBundle loadNibNamed: @"SSHTunnel" owner: ssht ];
    [ ssht displayWindow ];
    [ ssht autorelease ];
}

@end
