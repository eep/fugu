/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Cocoa/Cocoa.h>

@class SSHTunnelAuth;

@interface SSHTunnel : NSObject
{
    IBOutlet NSProgressIndicator *authProgBar;
    IBOutlet NSTextField 	*authProgMsg;
    IBOutlet NSTextField 	*passErrorField;
    IBOutlet NSTextField 	*passPromptField;
    IBOutlet NSButton		*addToKeychainSwitch;
    IBOutlet NSView 		*passpromptView;
    IBOutlet NSTextField 	*passwordField;
    IBOutlet NSComboBox 	*remoteHostField;
    IBOutlet NSComboBox 	*remotePortField;
    IBOutlet NSTextField	*localPortField;
    IBOutlet NSPanel 		*sshtunnelSheet;
    IBOutlet NSTableView 	*sshTunnelsTable;
    IBOutlet NSPanel 		*sshtunnelWindow;
    IBOutlet NSView 		*tunnelCreationView;
    IBOutlet NSComboBox		*tunnelHostField;
    IBOutlet NSTextField 	*unknownHostKeyField;
    IBOutlet NSTextField 	*unknownHostMsgField;
    IBOutlet NSView 		*unknownHostView;
    IBOutlet NSTextField 	*usernameField;
    IBOutlet NSTextField	*tunnelPortField;
    IBOutlet NSPopUpButton	*serviceFavoritePopUp;
    
    /* add service sheet */
    IBOutlet NSPanel		*addServiceSheet;
    IBOutlet NSTextField	*newServicePort;
    IBOutlet NSTextField	*newServiceName;
    
    IBOutlet NSPopUpButton	*sshTunnelInfoButton;
    
    IBOutlet NSProgressIndicator *connectProgBar;
    IBOutlet NSTextField	*connectMsg;
    
@private
    NSConnection		*connectionToTServer;
    SSHTunnelAuth		*ssh;
    BOOL			_firstPasswordPrompt;
    BOOL			_gotPasswordFromKeychain;
    pid_t			sshpid;
}

- ( void )setServer: ( id )serverObject;
- ( void )write: ( char * )buf;
- ( void )authenticateWithPrompt: ( char * )prompt;
- ( void )getContinueQueryWithString: ( NSString * )string;
- ( void )passError;
- ( void )connectionError: ( NSString * )errmsg;

- ( BOOL )firstPasswordPrompt;
- ( void )setFirstPasswordPrompt: ( BOOL )fp;
- ( BOOL )gotPasswordFromKeychain;
- ( void )setGotPasswordFromKeychain: ( BOOL )gp;

- ( void )displayWindow;

- ( IBAction )authenticate: ( id )sender;
- ( IBAction )acceptHost: ( id )sender;
- ( IBAction )cancelTunnelCreation: ( id )sender;
- ( IBAction )closeTunnel: ( id )sender;
- ( IBAction )refuseHost: ( id )sender;
- ( IBAction )startTunnel: ( id )sender;

- ( void )setSSHPID: ( pid_t )pid;

- ( void )tunnelCreated;
- ( void )addTunneledHostToDefaults: ( NSString * )rHost;

#ifdef notdef
- ( IBAction )cancelServiceAdd: ( id )sender;
- ( void )addService;
- ( IBAction )addService: ( id )sender;
- ( void )reloadServiceFavorites;
#endif /* notdef */

//- ( IBAction )selectFromFavorites: ( id )sender;

@end
