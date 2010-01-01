/*
 * Copyright (c) 2006 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Cocoa/Cocoa.h>

#define SFTPPrefsChangedNotification	@"SFTPPrefsChangedNotification"

@class SFTPPrefTableView;
@class UMArrayController;

@interface SFTPPrefs : NSObject
{
    IBOutlet NSPanel 		*prefPanel;
    IBOutlet NSTabView		*prefTabView;

    IBOutlet NSBox		*prefGeneralPaneBox;
	IBOutlet NSTextField	*prefDefaultLDir;
    
    IBOutlet NSBox		*prefFavoritesPaneBox;
	IBOutlet SFTPPrefTableView 	*prefFavTable;
    
    IBOutlet NSBox		*prefFilesPaneBox;
	IBOutlet NSPopUpButton	*prefTextEditorPopUp;
    
    IBOutlet NSBox		*prefKnownHostsPaneBox;
	IBOutlet UMArrayController	*prefKnownHostsArrayController;
	IBOutlet SFTPPrefTableView	*prefKnownHostsListTable;
	IBOutlet NSSearchField		*prefKnownHostsSearchField;

    NSMutableArray		*knownHosts;
    
@private
    NSMutableArray		*favs;
}

- ( IBAction )chooseDefaultLocalDirectory: ( id )sender;

- ( IBAction )addFavorite: ( id )sender;
- ( IBAction )deleteFavorite: ( id )sender;

- ( void )readKnownHosts;
- ( IBAction )saveKnownHosts: ( id )sender;

- ( void )readFavorites;

- ( void )showGeneralPreferences: ( id )sender;

- ( void )showPreferencePanel;

@end
