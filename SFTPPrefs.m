/*
 * Copyright (c) 2006 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#include <ApplicationServices/ApplicationServices.h>

#import "SFTPPrefs.h"
#import "NSMutableDictionary(Fugu).h"
#import "SFTPPrefTableView.h"
#import "UMArrayController.h"

#import "NSError-UMAdditions.h"
#import "NSPanel(Resizing).h"
#import "NSString(SSHAdditions).h"
#import "NSWorkspace(LaunchServices).h"

#include <sys/param.h>
#include <string.h>
#include <unistd.h>
#include "argcargv.h"

#define SFTPPrefToolbarGeneralIdentifier	@"generalprefs"
#define SFTPPrefToolbarFavoritesIdentifier	@"favoritesprefs"
#define SFTPPrefToolbarKnownHostsIdentifier	@"knownhostprefs"
#define SFTPPrefToolbarFilesIdentifier		@"fileeditingprefs"
#define SFTPPrefToolbarTransfersIdentifier	@"transfersprefs"

extern int		errno;

@implementation SFTPPrefs

+ ( void )initialize
{
    [[ NSUserDefaults standardUserDefaults ] registerDefaults:
	    [ NSDictionary dictionaryWithObjectsAndKeys:
	    @"/usr/bin", @"ExecutableSearchPath", 
	    [ NSArray arrayWithObject: @"/usr/bin" ],
	    @"ExecutableSearchPaths", nil ]];
}

- ( id )init
{  
    self = [ super init ];
    
    if ( self ) {
	knownHosts = [ NSMutableArray array ];
    }
    
    return( self );
}

- ( void )showPreferencePanel
{
    [ prefPanel makeKeyAndOrderFront: nil ];
}

- ( void )toolbarSetup
{
    NSToolbar *preftbar = [[[ NSToolbar alloc ] initWithIdentifier:
				@"SFTPPrefToolbar" ] autorelease ];
    
    [ preftbar setAllowsUserCustomization: NO ];
    [ preftbar setAutosavesConfiguration: NO ];
    [ preftbar setDisplayMode: NSToolbarDisplayModeIconAndLabel ];
    
    [ preftbar setDelegate: self ];
    [ prefPanel setToolbar: preftbar ];
}

- ( void )awakeFromNib
{
    NSTableColumn	    *tableColumn = [ prefFavTable tableColumnWithIdentifier: @"ssh1" ];
    NSButtonCell	    *protoCell = [[[ NSButtonCell alloc ]
                                            initTextCell: @"" ] autorelease ];
                                            
    [ protoCell setButtonType: NSSwitchButton ];
    [ protoCell setEditable: YES ];
    if ( tableColumn ) {
        [ tableColumn setDataCell: protoCell ];
    }
    tableColumn = [ prefFavTable tableColumnWithIdentifier: @"compress" ];
    if ( tableColumn ) {
        [ tableColumn setDataCell: protoCell ];
    }
    
    tableColumn = [[ prefKnownHostsListTable tableColumns ] objectAtIndex: 0 ];
    [[ tableColumn dataCell ] setWraps: YES ];
    
    favs = [[ NSMutableArray alloc ] init ];

    [ prefFavTable setDelegate: self ];
    [ prefFavTable setDataSource: self ];
    
    [ self toolbarSetup ];
    [ self readFavorites ];
    
    [ prefFavTable reloadData ];
    [ self showGeneralPreferences: nil ];
    [ prefPanel center ];
    [ prefPanel makeKeyAndOrderFront: nil ];
}

/**/
/* required toolbar delegate methods */
/**/

- ( NSToolbarItem * )toolbar: ( NSToolbar * )toolbar itemForItemIdentifier: ( NSString * )itemIdent willBeInsertedIntoToolbar: ( BOOL )flag
{
    NSToolbarItem *preftbarItem = [[[ NSToolbarItem alloc ]
                                    initWithItemIdentifier: itemIdent ] autorelease ];
    
    if ( [ itemIdent isEqualToString: SFTPPrefToolbarGeneralIdentifier ] ) {
        [ preftbarItem setLabel:
                NSLocalizedStringFromTable( @"General", @"SFTPPrefToolbar",
                                            @"General" ) ];
        [ preftbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"General", @"SFTPPrefToolbar",
                                            @"General" ) ];
        [ preftbarItem setToolTip:
                NSLocalizedStringFromTable( @"Show General Preferences", @"SFTPPrefToolbar",
                                            @"Show General Preferences" ) ];
        [ preftbarItem setImage: [ NSImage imageNamed: @"generalprefs.png" ]];
        [ preftbarItem setAction: @selector( showGeneralPreferences: ) ];
        [ preftbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPPrefToolbarFavoritesIdentifier ] ) {
        [ preftbarItem setLabel:
                NSLocalizedStringFromTable( @"Favorites", @"SFTPPrefToolbar",
                                            @"Favorites" ) ];
        [ preftbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"Favorites", @"SFTPPrefToolbar",
                                            @"Favorites" ) ];
        [ preftbarItem setToolTip:
                NSLocalizedStringFromTable( @"Show Favorites", @"SFTPPrefToolbar",
                                            @"Show Favorites" ) ];
        [ preftbarItem setImage: [ NSImage imageNamed: @"favoritesprefs.png" ]];
        [ preftbarItem setAction: @selector( showFavorites: ) ];
        [ preftbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPPrefToolbarTransfersIdentifier ] ) {
	[ preftbarItem setLabel:
                NSLocalizedStringFromTable( @"Transfers", @"SFTPPrefToolbar",
                                            @"Transfers" ) ];
        [ preftbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"Transfers", @"SFTPPrefToolbar",
                                            @"Transfers" ) ];
        [ preftbarItem setToolTip:
                NSLocalizedStringFromTable( @"Show Transfer Preferences", @"SFTPPrefToolbar",
                                            @"Show Transfer Preferences" ) ];
        [ preftbarItem setImage: [ NSImage imageNamed: @"transfers.png" ]];
        [ preftbarItem setAction: @selector( showTransfersPrefs: ) ];
        [ preftbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPPrefToolbarFilesIdentifier ] ) {
	[ preftbarItem setLabel:
                NSLocalizedStringFromTable( @"Files", @"SFTPPrefToolbar",
                                            @"Files" ) ];
        [ preftbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"Files", @"SFTPPrefToolbar",
                                            @"Files" ) ];
        [ preftbarItem setToolTip:
                NSLocalizedStringFromTable( @"Show Text File Editing Preferences", @"SFTPPrefToolbar",
                                            @"Show Text File Editing Preferences" ) ];
        [ preftbarItem setImage: [ NSImage imageNamed: @"files.png" ]];
        [ preftbarItem setAction: @selector( showFilesPrefs: ) ];
        [ preftbarItem setTarget: self ];
    } else if ( [ itemIdent isEqualToString: SFTPPrefToolbarKnownHostsIdentifier ] ) {
	[ preftbarItem setLabel:
                NSLocalizedStringFromTable( @"Known Hosts", @"SFTPPrefToolbar",
                                            @"Known Hosts" ) ];
        [ preftbarItem setPaletteLabel:
                NSLocalizedStringFromTable( @"Known Hosts", @"SFTPPrefToolbar",
                                            @"Known Hosts" ) ];
        [ preftbarItem setToolTip:
                NSLocalizedStringFromTable( @"Known Host Manager", @"SFTPPrefToolbar",
                                            @"Known Host Manager" ) ];
        [ preftbarItem setImage: [ NSImage imageNamed: @"knownhosts.png" ]];
        [ preftbarItem setAction: @selector( showKnownHosts: ) ];
        [ preftbarItem setTarget: self ];
    }
            
    return( preftbarItem );
}

- ( BOOL )validateToolbarItem: ( NSToolbarItem * )tItem
{
    return( YES );
}

- ( NSArray * )toolbarDefaultItemIdentifiers: ( NSToolbar * )toolbar
{
    NSArray	*tmp = [ NSArray arrayWithObjects:
                            SFTPPrefToolbarGeneralIdentifier,
                            SFTPPrefToolbarFavoritesIdentifier,
			    SFTPPrefToolbarFilesIdentifier,
			    SFTPPrefToolbarKnownHostsIdentifier, nil ];
                            
    return( tmp );
}

- ( NSArray * )toolbarAllowedItemIdentifiers: ( NSToolbar * )toolbar
{
    NSArray	*tmp = [ NSArray arrayWithObjects:
                            SFTPPrefToolbarGeneralIdentifier,
                            SFTPPrefToolbarFavoritesIdentifier,
			    SFTPPrefToolbarFilesIdentifier,
			    SFTPPrefToolbarKnownHostsIdentifier, nil ];
                            
    return( tmp );
}

- ( NSArray * )toolbarSelectableItemIdentifiers: ( NSToolbar * )toolbar
{
    NSArray	*tmp = [ NSArray arrayWithObjects:
                            SFTPPrefToolbarGeneralIdentifier,
                            SFTPPrefToolbarFavoritesIdentifier,
			    SFTPPrefToolbarFilesIdentifier,
			    SFTPPrefToolbarKnownHostsIdentifier, nil ];
                            
    return( tmp );
}
/* end required toolbar delegate methods */

- ( void )showGeneralPreferences: ( id )sender
{
    NSTabViewItem		*item;
    int				index;
    
    index = [ prefTabView indexOfTabViewItemWithIdentifier: @"General" ];
    item = [ prefTabView tabViewItemAtIndex: index ];
    
    [ prefTabView selectTabViewItemWithIdentifier: @"DummyTab" ];
    [ prefPanel resizeForContentView: prefGeneralPaneBox ];
    [ item setView: prefGeneralPaneBox ];
    [ prefTabView selectTabViewItemWithIdentifier: @"General" ];
    
    [ prefPanel setTitle: NSLocalizedString( @"Fugu: General Preferences",
			    @"Fugu: General Preferences" ) ];
}

- ( void )showFavorites: ( id )sender
{
    NSTabViewItem		*item;
    int				index;
    
    index = [ prefTabView indexOfTabViewItemWithIdentifier: @"Favorites" ];
    item = [ prefTabView tabViewItemAtIndex: index ];
    
    [ prefTabView selectTabViewItemWithIdentifier: @"DummyTab" ];
    [ prefPanel resizeForContentView: prefFavoritesPaneBox ];
    [ item setView: prefFavoritesPaneBox ];
    [ prefTabView selectTabViewItemWithIdentifier: @"Favorites" ];
    
    [ prefPanel setTitle:
	NSLocalizedString( @"Fugu: Favorites Editor",
			    @"Fugu: Favorites Editor" ) ];
    [[ prefFavTable window ] makeFirstResponder: prefFavTable ];
}

- ( void )showFilesPrefs: ( id )sender
{
    int			i;
    NSString		*editor = nil;
    NSBundle            *bundle = [ NSBundle bundleForClass: [ self class ]];
    NSDictionary        *editorPlist = nil;
    NSArray             *editorArray = nil;
    NSTabViewItem	*item;
    int			index;
    
    editorPlist = [ NSDictionary dictionaryWithContentsOfFile:
                    [ bundle pathForResource: @"ODBEditors" ofType: @"plist" ]];
    if ( ! editorPlist ) {
	[ NSError displayError:
		LOCALSTR( @"Failed to load list of ODB editors" ) ];
        return;
    }
    editorArray = [ editorPlist objectForKey: @"ODBEditors" ];
    
    if (( editor = [[ NSUserDefaults standardUserDefaults ]
			objectForKey: @"ODBTextEditor" ] ) == nil ) {
	editor = @"BBEdit";
    }

    [ prefTextEditorPopUp removeAllItems ];
    
    for ( i = 0; i < [ editorArray count ]; i++ ) {
        NSString    *bundleID = [[ editorArray objectAtIndex: i ] objectForKey: @"ODBEditorBundleID" ];
        NSString    *name = [[ editorArray objectAtIndex: i ] objectForKey: @"ODBEditorName" ];
        NSString    *signature = [[ editorArray objectAtIndex: i ] objectForKey: @"ODBEditorCreatorCode" ];
        NSImage     *odbIcon = nil;
        NSURL       *appURL;
        NSMenu      *popupMenu = [ prefTextEditorPopUp menu ];
        NSMenuItem  *menuItem = nil;
        const char  *sig;
        OSType      cc;
        
        if ( signature ) {
            sig = [ signature UTF8String ];
            cc = *(OSType *)sig;
        } else {
            cc = kLSUnknownCreator;
        }
        
        if ( [[ NSWorkspace sharedWorkspace ]
                launchServicesFindApplicationForCreatorType: cc
                bundleID: ( CFStringRef )bundleID appName: ( CFStringRef )name
                foundAppRef: NULL foundAppURL: ( CFURLRef * )&appURL ] ) {
            odbIcon = [[ NSWorkspace sharedWorkspace ] iconForFile: [ appURL path ]];
        } else if ( [ bundleID isEqualToString: @"-" ] ) {
            odbIcon = [[ NSWorkspace sharedWorkspace ] iconForFile:
                        [[ editorArray objectAtIndex: i ] objectForKey: @"ODBEditorPath" ]];
        } else {
            odbIcon = [[[ NSImage alloc ] initWithSize: NSMakeSize( 16.0, 16.0 ) ] autorelease ];
        }
        
        menuItem = [[ NSMenuItem alloc ] initWithTitle: name action: NULL keyEquivalent: @"" ];
        if ( odbIcon ) {
            [ odbIcon setScalesWhenResized: YES ];
            [ odbIcon setSize: NSMakeSize( 16.0, 16.0 ) ];
            [ menuItem setImage: odbIcon ];
        }
        
        [ popupMenu addItem: menuItem ];
        [ menuItem release ];
    }

    [ prefTextEditorPopUp selectItemWithTitle: editor ];

    index = [ prefTabView indexOfTabViewItemWithIdentifier: @"Files" ];
    item = [ prefTabView tabViewItemAtIndex: index ];
    
    [ prefTabView selectTabViewItemWithIdentifier: @"DummyTab" ];
    [ prefPanel resizeForContentView: prefFilesPaneBox ];
    [ item setView: prefFilesPaneBox ];
    [ prefTabView selectTabViewItemWithIdentifier: @"Files" ];
    
    [ prefPanel setTitle: NSLocalizedString( @"Fugu Preferences: File Editing",
                                @"Fugu Preferences: File Editing" ) ];
}


- ( void )showKnownHosts: ( id )sender
{
    NSTabViewItem		*item;
    int				index;
    
    [ self readKnownHosts ];
    
    index = [ prefTabView indexOfTabViewItemWithIdentifier: @"KnownHosts" ];
    item = [ prefTabView tabViewItemAtIndex: index ];
    
    [ prefTabView selectTabViewItemWithIdentifier: @"DummyTab" ];
    [ prefPanel resizeForContentView: prefKnownHostsPaneBox ];
    [ item setView: prefKnownHostsPaneBox ];
    [ prefTabView selectTabViewItemWithIdentifier: @"KnownHosts" ];
    
    [ prefPanel setTitle: NSLocalizedString(
			    @"Fugu Preferences: SSH Known Hosts Editor",
			    @"Fugu Preferences: SSH Known Hosts Editor" ) ];
}

- ( IBAction )chooseDefaultLocalDirectory: ( id )sender
{
    NSOpenPanel		*op = [ NSOpenPanel openPanel ];
    
    [ op setCanChooseFiles: NO ];
    [ op setCanChooseDirectories: YES ];
    [ op setTitle: NSLocalizedString( @"Choose a Default Folder",
					@"Choose a Default Folder" ) ];
    [ op setPrompt: NSLocalizedString( @"Choose", @"Choose" ) ];
    
    [ op beginSheetForDirectory: nil
        file: nil
        types: nil
        modalForWindow: prefPanel
        modalDelegate: self
        didEndSelector: @selector( defaultDirOpenPanelDidEnd:returnCode:contextInfo: )
        contextInfo: nil ];
}

- ( void )defaultDirOpenPanelDidEnd: ( NSOpenPanel * )sheet
	returnCode: ( int )rc contextInfo: ( void * )contextInfo
{
    [ sheet orderOut: nil ];
    [ NSApp endSheet: sheet ];
    [ prefPanel makeKeyAndOrderFront: nil ];
    
    switch ( rc ) {
    case NSOKButton:
        [ prefDefaultLDir setStringValue:
		[[ sheet filenames ] objectAtIndex: 0 ]];
	[[ NSUserDefaults standardUserDefaults ] setObject:
		[ prefDefaultLDir stringValue ] forKey: @"defaultldir" ];
        break;
	
    case NSCancelButton:
        break;
    }
}

- ( void )readKnownHosts
{
    FILE			*knfp = NULL;
    char			buf[ LINE_MAX ];
    NSMutableAttributedString	*keyAttrString, *serverAttrString;
    NSMutableParagraphStyle	*paragraphStyle;
    NSString			*knownhostspath = [ NSString stringWithFormat:
						    @"%@/.ssh/known_hosts",
						    NSHomeDirectory() ];
    
    if (( knfp = fopen( [ knownhostspath UTF8String ], "r" )) == NULL ) {
	[ NSError displayError: LOCALSTR( @"Failed to open %@: %s" ),
		    knownhostspath, strerror( errno ) ];
	return;
    }
    
    [ prefKnownHostsArrayController removeObjects: knownHosts ];
    [ knownHosts removeAllObjects ];
    
    paragraphStyle = [[ NSParagraphStyle defaultParagraphStyle ] mutableCopy ];
    
    while ( fgets( buf, LINE_MAX, knfp ) != NULL ) {
	int	tac;
	char	*line = NULL, **targv;
	
	if (( line = strdup( buf )) == NULL ) {
	    perror( "strdup" );
	    exit( 2 );
	}
	
	if (( tac = argcargv( line, &targv )) < 3 ) {
	    free( line );
	    continue;
	}
	
	/* set appropriate linebreak modes for display */
	[ paragraphStyle setLineBreakMode: NSLineBreakByTruncatingTail ];
	serverAttrString = [[ NSMutableAttributedString alloc ] initWithString:
			[ NSString stringWithUTF8String: targv[ 0 ]]];
	[ serverAttrString addAttribute: NSParagraphStyleAttributeName
		value: paragraphStyle range: NSMakeRange( 0, strlen( targv[ 0 ] )) ];
	
	[ paragraphStyle setLineBreakMode: NSLineBreakByCharWrapping ];
	keyAttrString = [[ NSMutableAttributedString alloc ] initWithString:
			[ NSString stringWithUTF8String: targv[ 2 ]]];
	[ keyAttrString addAttribute: NSParagraphStyleAttributeName
		value: paragraphStyle range: NSMakeRange( 0, strlen( targv[ 2 ] )) ];
		
	[ knownHosts addObject: [ NSMutableDictionary dictionaryWithObjectsAndKeys:
		serverAttrString, @"hostid",
		[ NSString stringWithUTF8String: targv[ 0 ]], @"hostidString",
		[ NSString stringWithUTF8String: targv[ 1 ]], @"keytype",
		keyAttrString, @"key", nil ]];
	[ serverAttrString release ];
	[ keyAttrString release ];
	
	free( line );
    }
    
    [ paragraphStyle release ];
    ( void )fclose( knfp );
    
    [ prefKnownHostsArrayController setContent: knownHosts ];
}

- ( IBAction )saveKnownHosts: ( id )sender
{
    char		khpath[ MAXPATHLEN ];
    char		khpathtmp[ MAXPATHLEN ];
    int			i, fd;
    FILE		*fp;
    
    if ( snprintf( khpath, MAXPATHLEN, "%s/.ssh/known_hosts",
	    [ NSHomeDirectory() UTF8String ] ) >= MAXPATHLEN ) {
	[ NSError displayError: LOCALSTR( @"%s: path too long" ), khpath ];
	return;
    }
    
    if ( snprintf( khpathtmp, MAXPATHLEN, "%s.XXXXXX", khpath ) >= MAXPATHLEN ) {
	[ NSError displayError: LOCALSTR( @"%s.XXXXXX: path too long" ),
		khpathtmp ];
	return;
    }
    
    if (( fd = mkstemp( khpathtmp )) < 0 ) {
	[ NSError displayError: LOCALSTR( @"mkstemp %s: %s" ), khpathtmp,
		strerror( errno ) ];
	return;
    }
    
    if (( fp = fdopen( fd, "w+" )) == NULL ) {
	( void )close( fd );
	[ NSError displayError: LOCALSTR( @"fdopen: %s" ), strerror( errno ) ];
	return;
    }
    
    for ( i = 0; i < [ knownHosts count ]; i++ ) {
	NSDictionary	*dict = [ knownHosts objectAtIndex: i ];
	
	fprintf( fp, "%s %s %s\n",
		( char * )[[ dict objectForKey: @"hostidString" ] UTF8String ],
		( char * )[[ dict objectForKey: @"keytype" ] UTF8String ],
		( char * )[[[ dict objectForKey: @"key" ] string ] UTF8String ] );
    }
    if ( fclose( fp ) != 0 ) {
	[ NSError displayError: LOCALSTR( @"fclose: %s" ), strerror( errno ) ];
	return;
    }
    
    if ( rename( khpathtmp, khpath ) != 0 ) {
	[ NSError displayError: LOCALSTR( @"Rename %s to %s: %s" ),
		khpathtmp, khpath, strerror( errno ) ];
    }
}

- ( void )readFavorites
{
    int			i;
    NSMutableArray	*favarray;
    id			fobj;
    
    [ favs removeAllObjects ];
    favarray = [[ NSUserDefaults standardUserDefaults ] objectForKey: @"Favorites" ];
    
    for ( i = 0; i < [ favarray count ]; i++ ) {
        fobj = [ favarray objectAtIndex: i ];
        
        if ( [ fobj isKindOfClass: [ NSString class ]] ) {
            NSMutableDictionary	*dict;
            
            dict = [ NSMutableDictionary favoriteDictionaryFromHostname: fobj ];
            [ favarray replaceObjectAtIndex: i withObject: dict ];
        }
    }
    
    [ favs addObjectsFromArray: favarray ];
    [[ NSUserDefaults standardUserDefaults ] setObject: favs forKey: @"Favorites" ];
}

- ( IBAction )addFavorite:( id )sender
{
    NSMutableDictionary		*dict;
    
    dict = [ NSMutableDictionary dictionaryWithObjectsAndKeys:
                                    @"newserver", @"nick",
                                    @"newserver.local", @"host",
                                    @"", @"user",
                                    @"", @"port",
                                    @"", @"dir", nil ];
    [ favs addObject: dict ];
    [ prefFavTable reloadData ];
    [ prefFavTable selectRow: ( [ favs count ] - 1 ) byExtendingSelection: NO ];
    [ prefFavTable editColumn: 0 row: ( [ favs count ] - 1 ) withEvent: nil select: YES ];
}

- ( IBAction )deleteFavorite: ( id )sender
{
    if ( [ prefFavTable selectedRow ] < 0 ) return;
    if ( [ favs count ] > 0 ) {
        [ favs removeObjectAtIndex: [ prefFavTable selectedRow ]];
    }
    [[ NSUserDefaults standardUserDefaults ] setObject: favs forKey: @"Favorites" ];
    [[ NSNotificationCenter defaultCenter ] postNotificationName: SFTPPrefsChangedNotification
                                            object: nil ];
    [ prefFavTable reloadData ];
}

- ( IBAction )dismissPrefPanel: ( id )sender
{
    [ prefPanel close ];
}

/* tableview datasource methods */
- ( int )numberOfRowsInTableView: ( NSTableView * )aTableView
{
    if ( [ aTableView isEqual: prefFavTable ] ) {
	return( [ favs count ] );
    }
    
    return( 0 );
}

- ( id )tableView: ( NSTableView * )aTableView
        objectValueForTableColumn: ( NSTableColumn * )aTableColumn
        row: ( int )rowIndex
{
    NSMutableArray      *array = nil;
    
    /* XXX may be able to dispense with some of this by using bindings */
    if ( [ aTableView isEqual: prefFavTable ] ) {
	if ( [[ favs objectAtIndex: rowIndex ] isKindOfClass: [ NSString class ]] 
		&& [[ aTableColumn identifier ] isEqualToString: @"host" ] ) {
	    return( [ favs objectAtIndex: rowIndex ] );
	}
	array = favs;
    }

    return( [[ array objectAtIndex: rowIndex ]
                objectForKey: [ aTableColumn identifier ]] );
}

- ( void )tableView: ( NSTableView * )aTableView
            setObjectValue: ( id )anObject
            forTableColumn: ( NSTableColumn * )aTableColumn
            row: ( int )rowIndex
{
    NSMutableDictionary		*dict = nil;
    
    if ( [ aTableView isEqual: prefFavTable ] ) {
	if ( [ favs count ] <= 0 || [ favs count ] <= rowIndex ) return;
	
	if ( [[ favs objectAtIndex: rowIndex ] isKindOfClass: [ NSString class ]]
		&& [[ aTableColumn identifier ] isEqualToString: @"fhost" ] ) {
	    [ favs replaceObjectAtIndex: rowIndex
		    withObject:
			[ NSMutableDictionary favoriteDictionaryFromHostname:
					[ favs objectAtIndex: rowIndex ]]];
	    return;
	}
	
	dict = [[ favs objectAtIndex: rowIndex ] mutableCopy ];
	
        [ dict setObject: anObject forKey: [ aTableColumn identifier ]];
        
	[ favs replaceObjectAtIndex: rowIndex withObject: dict ];
	[ dict release ];
	[[ NSUserDefaults standardUserDefaults ]
	    setObject: favs forKey: @"Favorites" ];
	[[ NSNotificationCenter defaultCenter ]
	    postNotificationName: SFTPPrefsChangedNotification object: nil ];
    }
}

@end
