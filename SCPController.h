/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Cocoa/Cocoa.h>

#import "SCPTransfer.h"
#import "UMDragDropImageView.h"
#import "UMTextField.h"

@class SCPTransfer;

@interface SCPController : NSObject
{
    IBOutlet NSTextField 	*destPathField;
    IBOutlet NSTextField 	*destPortField;
    IBOutlet NSComboBox 	*destServerField;
    IBOutlet NSTextField	*destUserNameField;
    IBOutlet UMTextField 	*localFileField;
    IBOutlet UMDragDropImageView 	*localFileImageView;
    IBOutlet NSPopUpButton	*recentCopiesList;
    IBOutlet NSMatrix		*copyType;
    
    IBOutlet NSTextField 	*passPromptField;
    IBOutlet NSView 		*passpromptView;
    IBOutlet NSTextField 	*passwordField;
    IBOutlet NSTextField	*passErrorField;
    IBOutlet NSButton		*addToKeychainSwitch;
    
    IBOutlet NSProgressIndicator *progBar;
    IBOutlet NSTextField	*percentDoneField;
    IBOutlet NSTextField	*etaField;
    IBOutlet NSTextField	*bytesCopiedField;
    IBOutlet NSTextField 	*connectProgMsg;
    IBOutlet NSView 		*connectProgView;
    
    IBOutlet NSView		*unknownHostView;
    IBOutlet NSTextField	*unknownHostMsgField;
    IBOutlet NSTextField	*unknownHostKeyField;
    
    IBOutlet NSPanel 		*scpSheet;
    IBOutlet NSWindow 		*scpWindow;
    
    /* log outlets */
    IBOutlet NSDrawer		*scpLogDrawer;
    IBOutlet NSTextView		*scpLogField;
    
    IBOutlet NSProgressIndicator *authProgBar;
    
@private
    NSConnection		*connectionToTServer;
    NSString			*scpFileName;
    SCPTransfer			*scp;
    double			bytescopied, scpFileSize;
    
    BOOL			_firstPasswordPrompt;
    BOOL			_gotPasswordFromKeychain;
    
    id				_scpDelegate;
    pid_t			scppid;
    int				masterfd;
}

- ( void )setServer: ( id )serverObject;

- ( void )authenticateWithPrompt: ( char * )prompt;
- ( IBAction )authenticate: ( id )sender;
- ( void )write: ( char * )buf;
- ( void )passError;

- ( void )sessionError: ( NSString * )err;

- ( IBAction )beginSCP: ( id )sender;
- ( IBAction )cancelSCP: ( id )sender;
- ( IBAction )cancelSCPDialog: ( id )sender;
- ( IBAction )chooseLocalFile: ( id )sender;

- ( void )getSecureCopyWindowForFile: ( NSString * )filename
            scpType: ( int )scpType copyToPath: ( NSString * )destPath
            fromHost: ( NSString * )rhost userName: ( NSString * )user
            delegate: ( id )delegate;
- ( void )getContinueQueryWithString: ( NSString * )string;
- ( IBAction )acceptHost: ( id )sender;
- ( IBAction )refuseHost: ( id )sender;

- ( BOOL )firstPasswordPrompt;
- ( void )setFirstPasswordPrompt: ( BOOL )fp;
- ( BOOL )gotPasswordFromKeychain;
- ( void )setGotPasswordFromKeychain: ( BOOL )gp;

- ( void )secureCopy;
- ( void )fileCopying: ( NSString * )fname
            updateWithPercentDone: ( char * )pc
            eta: ( char * )eta
            bytesCopied: ( char * )bytes;
- ( void )secureCopyFinishedWithStatus: ( int )status;
/* on completion, SCPController class calls delegate method -(void)scpFinished */

- ( void )clearLog;
- ( void )addToLog: ( NSString * )buf;

- ( void )setSCPPID: ( pid_t )pid;
- ( void )setMasterFD: ( int )fd;

- ( id )delegate;
- ( void )setDelegate: ( id )delegate;

@end

/* delegate methods */
@interface NSObject(SCPControllerDelegate)
- ( void )scpFinished;
@end
