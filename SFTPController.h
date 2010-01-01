/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Cocoa/Cocoa.h>

#import "SFTPMainWindow.h"
#import "SFTPPrefs.h"
#import "SFTPTableView.h"
#import "SFTPImagePreviewPanel.h"
#import "SFTPImageView.h"

#define SFTPToolbarLocalHomeIdentifier 		@"lhome"
#define SFTPToolbarNewDirIdentifier 		@"newdir"
#define SFTPToolbarDeleteIdentifier		@"delete"
#define SFTPToolbarConnectIdentifier		@"connect"
#define SFTPToolbarInfoIdentifier		@"info"
#define SFTPToolbarRemoteHomeIdentifier		@"rhome"
#define SFTPToolbarRefreshIdentifier		@"reload"
#define SFTPToolbarDownloadIdentifier		@"download"
#define SFTPToolbarUploadIdentifier		@"upload"
#define SFTPToolbarGotoIdentifier		@"gotodir"
#define SFTPToolbarLocalHistoryIdentifier	@"lhistory"
#define SFTPToolbarRemoteHistoryIdentifier	@"rhistory"
#define SFTPToolbarRemoteItemPreviewIdentifier	@"preview"
#define SFTPToolbarEditDocumentIdentifier	@"edit"

@class 		SFTPTServer;
@class		SCPController;

@interface 	SFTPController : NSObject
{
    /* console panel outlets */
    IBOutlet NSPanel			*logPanel;
    IBOutlet NSTextView			*logField;
    IBOutlet NSButton			*commandButton;
    IBOutlet NSTextField 		*manualComField;
    
    /* new dir panel outlets */
    IBOutlet NSPanel			*newDirPanel;
    IBOutlet NSTextField		*newDirNameField;
    IBOutlet NSButton			*newDirCreateButton;
    IBOutlet NSButton			*localDirCreateButton;
    IBOutlet NSButton			*remoteDirCreateButton;
    
    /* go to dir panel outlets */
    IBOutlet NSPanel			*gotoDirPanel;
    IBOutlet NSComboBox			*gotoDirNameField;
    IBOutlet NSButton			*gotoButton;
    IBOutlet NSButton			*localGotoButton;
    IBOutlet NSButton			*remoteGotoButton;
    
    /* upload progress panel outlets */
    IBOutlet NSPanel			*uploadProgPanel;
    IBOutlet NSTextField		*uploadProgName;
    IBOutlet NSTextField		*uploadProgItemsLeft;
    IBOutlet NSTextField		*uploadTimeField;
    IBOutlet NSProgressIndicator	*uploadProgBar;
    IBOutlet NSTextField		*uploadProgInfo;
    
    /* download progress panel outlets */
    IBOutlet NSPanel			*downloadSheet;
    IBOutlet NSTextField		*downloadTextField;
    IBOutlet NSTextField		*downloadTimeField;
    IBOutlet NSProgressIndicator	*downloadProgBar;
    IBOutlet NSTextField		*downloadProgInfo;
    IBOutlet NSTextField		*downloadProgPercentDone;
    
    /* preview panel outlets */
    IBOutlet SFTPImagePreviewPanel	*imagePreviewPanel;
    IBOutlet NSBox			*imagePreviewBox;
    IBOutlet NSView			*imagePreviewView;
    IBOutlet SFTPImageView		*imagePreview;
    IBOutlet NSTextField		*imagePreviewTextField;
    
    /* info panel outlets */
    IBOutlet NSPanel			*infoPanel;
    IBOutlet NSTabView			*infoTabView;
        // local info fields
    IBOutlet NSImageView		*largeIcon;
    IBOutlet NSTextField		*modDateField;
    IBOutlet NSTextField	 	*groupField;
    IBOutlet NSTextField 		*ownerField;
    IBOutlet NSTextField 		*sizeField;
    IBOutlet NSTextField 		*typeField;
    IBOutlet NSTextField 		*permField;
    IBOutlet NSTextField 		*infoPathField;
    IBOutlet NSTextField		*whereField;
    IBOutlet NSButton 			*loReadSwitch;
    IBOutlet NSButton 			*loWriteSwitch;
    IBOutlet NSButton 			*loExecSwitch;
    IBOutlet NSButton 			*lgReadSwitch;
    IBOutlet NSButton 			*lgWriteSwitch;
    IBOutlet NSButton 			*lgExecSwitch;
    IBOutlet NSButton 			*laReadSwitch;
    IBOutlet NSButton 			*laWriteSwitch;
    IBOutlet NSButton 			*laExecSwitch;
        // remote info fields
    IBOutlet NSImageView		*rIcon;
    IBOutlet NSTextField		*rModDateField;
    IBOutlet NSTextField	 	*rGroupField;
    IBOutlet NSTextField 		*rOwnerField;
    IBOutlet NSTextField 		*rSizeField;
    IBOutlet NSTextField 		*rTypeField;
    IBOutlet NSTextField 		*rPermField;
    IBOutlet NSTextField 		*rInfoPathField;
    IBOutlet NSTextField		*rWhereField;
    IBOutlet NSButton			*roReadSwitch;
    IBOutlet NSButton			*roWriteSwitch;
    IBOutlet NSButton			*roExecSwitch;
    IBOutlet NSButton			*rgReadSwitch;
    IBOutlet NSButton			*rgWriteSwitch;
    IBOutlet NSButton			*rgExecSwitch;
    IBOutlet NSButton			*raReadSwitch;
    IBOutlet NSButton			*raWriteSwitch;
    IBOutlet NSButton			*raExecSwitch;
    
    /* main ui elements */
    //IBOutlet NSTextField		*remoteDirPath;
    IBOutlet NSProgressIndicator	*remoteProgBar;
    IBOutlet NSTextField		*remoteMsgField;
    IBOutlet NSBox			*sftpBrowserBox;
    IBOutlet NSBox			*localBox;
    IBOutlet NSBox			*remoteBox;
    
    /* local and remote views */
    IBOutlet NSView			*localView;
    IBOutlet NSView			*remoteView;
    IBOutlet NSPopUpButton		*rPathPopUp;
    IBOutlet NSPopUpButton		*lPathPopUp;
    IBOutlet NSTextField		*remoteColumnFooter;
    IBOutlet SFTPTableView 		*localBrowser;
    IBOutlet NSMenu			*localTableMenu;
    IBOutlet SFTPTableView	 	*remoteBrowser;
    IBOutlet NSMenu			*remoteTableMenu;
    
    IBOutlet id hostKeyUnauth;
    IBOutlet id unauthHostInfo;
    IBOutlet id	dotMenuItem;
    IBOutlet id infoMenuItem;
    IBOutlet id addToFavButton;
    IBOutlet id verifyConnectSheet;
    
    /* connecting view outlets */
    IBOutlet NSView			*connectingView;
    IBOutlet NSProgressIndicator	*connectingProgress;
    IBOutlet NSTextField		*connectingToField;
    
    IBOutlet SFTPMainWindow		*mainWindow;
    
    /* password prompt outlets */
    IBOutlet NSTextField 		*passErrorField;
    IBOutlet NSView	 		*passView;
    IBOutlet NSTextField		*passWord;
    IBOutlet NSTextField		*passHeader;
    IBOutlet NSProgressIndicator	*authProgBar;
    IBOutlet NSButton			*passAuthButton;
    IBOutlet NSButton			*passCancelButton;
    IBOutlet NSButton			*addToKeychainSwitch;
    
    /* login view outlets */
    IBOutlet NSView			*loginView;
    IBOutlet NSPopUpButton 		*popUpFavs;
    IBOutlet id remoteHost;
    IBOutlet id dotSwitch;
    IBOutlet id userName;
    IBOutlet NSTextField 		*portField;
    IBOutlet NSTextField		*loginDirField;
    IBOutlet NSButton			*connectButton;
    IBOutlet NSPopUpButton		*rendezvousPopUp;
    
    /* advanced connection outlets */
    IBOutlet NSView			*advConnectionView;
    IBOutlet NSBox			*advConnectionBox;
    IBOutlet NSTextField		*advAdditionalOptionsField;
    IBOutlet NSButton			*advForceSSH1Switch;
    IBOutlet NSButton			*advEnableCompressionSwitch;
    
    /* view information menu items */
    IBOutlet NSMenuItem			*viewGroupMenuItem;
    IBOutlet NSMenuItem			*viewModDateMenuItem;
    IBOutlet NSMenuItem			*viewModeMenuItem;
    IBOutlet NSMenuItem			*viewOwnerMenuItem;
    IBOutlet NSMenuItem			*viewSizeMenuItem;
    
@private
    /*
     * used to tell if the password in the keychain was wrong.
     * if so, don't keep turning to the keychain for the password.
     * prompt the user as usual, instead.
     */
    BOOL			firstPasswordPrompt;
    BOOL			gotPasswordFromKeychain;
    
    int				dotflag;

    NSConnection		*connectionToTServer;
    SFTPTServer			*tServer;
    
    SFTPPrefs			*prefs;
    
    SCPController		*scp;
    
    NSMutableDictionary		*userParameters;
    NSMutableDictionary 	*remoteFileInfo;
    NSString	 		*remoteDirBuf;
    NSString			*remoteHome;
    
    NSMutableArray		*remoteDirContents;
    NSMutableArray		*dotlessRDir;
    NSArray			*rSwitchArray;
    NSString			*remoteDirPath;
    NSMutableArray		*localDirContents;
    NSMutableArray		*dotlessLDir;
    NSString			*localDirPath;
    
    /* rendezvous */
    id				sshServiceBrowser;
    NSMutableArray		*services;
    
    /* documents being edited from the server */
    NSMutableArray		*editedDocuments;
    
    /* images being previewed from the server */
    NSString			*previewedImage;
    NSMutableArray		*cachedPreviews;
    
    /* menus for history */
    NSMenu			*localHistoryMenu;
    NSMenu			*remoteHistoryMenu;
    
    /* queues from which to dispatch items to the session */
    NSMutableArray		*uploadQueue;
    NSMutableArray		*downloadQueue;
    NSMutableArray		*removeQueue;
    
    /* images for display in browsers */
    NSImage			*dirImage;
    NSImage			*fileImage;
    NSImage			*linkImage;
    
    /* spring-loaded root path */
    NSString                    *_springLoadedRootPath;
    
    /* command queue */
    NSMutableArray              *_sftpCommandQueue;
}

- ( void )showUploadProgress;
- ( void )updateUploadProgress: ( int )endflag;
- ( void )removeFirstItemFromUploadQ;
- ( NSMutableArray * )uploadQ;
- ( void )prepareDirUpload: ( NSString * )dir;
- ( void )updateUploadProgressBarWithValue: ( double )value
	    amountTransfered: ( NSString * )amount
	    transferRate: ( NSString * )rate
	    ETA: ( NSString * )eta;

- ( void )removeFirstItemFromDownloadQ;
- ( NSMutableArray * )downloadQ;

- ( IBAction )sendPassword: ( id )sender;
- ( void )addPasswordToKeychain;
- ( BOOL )retrievePasswordFromKeychain;
- ( BOOL )firstPasswordPrompt;
- ( void )setFirstPasswordPrompt: ( BOOL )first;
- ( void )setGotPasswordFromKeychain: ( BOOL )rp;
- ( BOOL )gotPasswordFromKeychain;
- ( IBAction )cancelConnection: ( id )sender;
- ( IBAction )continueConnecting: ( id )sender;
- ( void )connectionError: ( NSString * )errmsg;
- ( void )sessionError: ( NSString * )errmsg;
- ( IBAction )toggleDots: ( id )sender;

- ( IBAction )toggleAdvConnectionView: ( id )sender;

- ( void )showConnectingInterface: ( id )sender;

- ( IBAction )toggleGoToButtons: ( id )sender;
- ( IBAction )getGotoDirPanel: ( id )sender;
- ( IBAction )gotoLocalDirectory: ( id )sender;
- ( IBAction )gotoRemoteDirectory: ( id )sender;
- ( IBAction )dismissGotoDirPanel: ( id )sender;

- ( IBAction )selectFromFavorites: ( id )sender;
- ( IBAction )addToFavorites: ( id )sender;

- ( IBAction )sftpConnect: ( id )sender;

- ( void )showDownloadProgressWithMessage: ( char * )msg;
- ( void )updateDownloadProgressBarWithValue: ( double )value
	    amountTransfered: ( NSString * )amount
	    transferRate: ( NSString * )rate
	    ETA: ( NSString * )eta;
- ( void )finishedDownload;

- ( IBAction )showItemFromHelpMenu: ( id )sender;

/* interaction related methods */
- ( void )uploadFiles: ( NSArray * )lfiles toDirectory: ( NSString * )rpath;
- ( void )downloadFiles: ( NSArray * )rpaths toDirectory: ( NSString * )lpath;
- ( IBAction )createNewDirectory: ( id )sender;
- ( IBAction )toggleDirCreationButtons: ( id )sender;
- ( IBAction )dismissNewDirPanel: ( id )sender;

/* spring-loaded folders */
- ( void )performSpringLoadedActionInTable: ( NSTableView * )table;
- ( void )setSpringLoadedRootPathInTable: ( NSTableView * )table;
- ( NSString * )springLoadedRootPath;

/* accessor methods for sftp command queue */
- ( void )queueSFTPCommand: ( const char * )fmt, ...;
- ( NSMutableArray * )SFTPCommandQueue;
- ( id )nextSFTPCommandFromQueue;

/* methods related to deleting items */
- ( IBAction )delete: ( id )sender;
- ( IBAction )deleteLocalFile: ( id )sender;
- ( IBAction )deleteRemoteFile: ( id )sender;
- ( void )deleteFirstItemFromRemoveQueue;
- ( NSMutableArray * )removeQ;

- ( IBAction )focusOnLocalPane: ( id )sender;
- ( IBAction )focusOnRemotePane: ( id )sender;

- ( IBAction )localBrowserSingleClick: ( id )browser;
- ( IBAction )localBrowserDoubleClick: ( id )browser;
- ( IBAction )uploadButtonClick: ( id )sender;
- ( IBAction )remoteBrowserSingleClick: ( id )browser;
- ( IBAction )remoteBrowserDoubleClick: ( id )browser;
- ( IBAction )downloadButtonClick: ( id )sender;
- ( IBAction )cdRemoteHome: ( id )sender;
- ( IBAction )cdLocalHome: ( id )sender;
- ( IBAction )remoteCdDotDot: ( id )sender;
- ( IBAction )localCdDotDot: ( id )sender;
- ( IBAction )cdFromLPathPopUp: ( id )sender;
- ( IBAction )cdFromRPathPopUp: ( id )sender;
- ( IBAction )refreshBrowsers: ( id )sender;

- ( void )changeToRemoteDirectory: ( NSString * )remotePath;
- ( void )changeDirectory: ( id )sender;
- ( void )dotdot: ( id )sender;

- ( IBAction )changeROwner: ( id )sender;
- ( IBAction )changeRGroup: ( id )sender;
- ( IBAction )changeRemoteMode: ( id )sender;

- ( IBAction )changeLOwnerAndGroup: ( id )sender;
- ( IBAction )changeLocalMode: ( id )sender;

- ( IBAction )renameLocalItem: ( id )sender;
- ( IBAction )renameRemoteItem: ( id )sender;

- ( void )getListing;
- ( void )setBusyStatusWithMessage: ( NSString * )message;
- ( void )finishedCommand;
- ( void )writeCommand: ( void * )cmd;
- ( IBAction )sendManualCommand: ( id )sender;

- ( void )setServer: ( id )serverObject;

- ( IBAction )showLogPanel: ( id )sender;
- ( void )clearLog;
- ( void )addToLog: ( NSString * )text;
- ( void )updateHostList;
- ( void )reloadDefaults;

- ( void )passError;
- ( void )setConnectedWindowTitle;
- ( IBAction )disconnect: ( id )sender;
- ( void )cleanUp;
- ( id )init;
//- ( void )mouseDown: ( NSEvent * )theEvent;

- ( void )localBrowserReloadForPath: ( NSString * )path;

- ( IBAction )toggleGroupColumn: ( id )sender;
- ( IBAction )toggleModDateColumn: ( id )sender;
- ( IBAction )toggleModeColumn: ( id )sender;
- ( IBAction )toggleOwnerColumn: ( id )sender;
- ( IBAction )toggleSizeColumn: ( id )sender;

- ( void )setRemotePathPopUp: ( NSString * )pwd;
- ( void )showRemoteFiles;
- ( void )loadRemoteBrowserWithItems: ( NSArray * )items;
- ( IBAction )getInfo: ( id )sender;
- ( void )remoteCheckSetup: ( NSString * )permissions;
- ( void )localCheckSetup: ( NSString * )octalmode;
- ( void )getContinueQueryForUnknownHost: ( NSDictionary * )hostInfo;
- ( void )requestPasswordWithPrompt: ( char * )header;
- ( void )enableFavButton: ( NSNotification * )aNotification;
- ( void )awakeFromNib;
- ( void )dealloc;

- ( IBAction )showPrefs: ( id )sender;

- ( int )matchingIndexForString: ( NSString * )string inTable: ( SFTPTableView * )table;
                
- ( IBAction )checkForUpdates: ( id )sender;

- ( void )scanForSSHServers: ( id )sender;
- ( IBAction )selectRendezvousServer: ( id )sender;

- ( IBAction )previewItem: ( id )sender;
- ( IBAction )previewLocalItem: ( id )sender;
- ( IBAction )previewRemoteItem: ( id )sender;
- ( void )setPreviewedImage: ( NSString * )imagepath;
- ( NSString * )previewedImage;
- ( void )displayPreview;
- ( void )addToCachedPreviews: ( NSDictionary *)cachedData;
- ( NSArray * )cachedPreviews;

- ( IBAction )editFile: ( id )sender;
- ( IBAction )openLocalFileInEditor: ( id )sender;
- ( IBAction )openRemoteFileInEditor: ( id )sender;
- ( void )ODBEditFile: ( NSString * )filepath remotePath: ( NSString * )remotepath;

- ( NSArray * )editedDocuments;
- ( void )addToEditedDocuments: ( NSString * )docpath remotePath: ( NSString * )rpath;
- ( void )removeFromEditedDocuments: ( NSString * )docpath;

/* other ssh related tools */
- ( IBAction )newSSHTunnel: ( id )sender;
- ( IBAction )secureCopy: ( id )sender;
- ( IBAction )scp: ( id )sender;
- ( void )scpLocalItem: ( NSString * )item toHost: ( NSString * )rhost
        userName: ( NSString * )user;
- ( void )scpRemoteItem: ( NSString * )rdir fromHost: ( NSString * )rhost
        toLocalPath: ( NSString * )ldir userName: ( NSString * )user;
- ( void )scpFinished; /* SCPController delegate method */

@end
