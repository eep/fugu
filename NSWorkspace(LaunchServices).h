/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Cocoa/Cocoa.h>
#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include <CoreFoundation/CoreFoundation.h>

@interface NSWorkspace(LaunchServices)

- ( BOOL )launchServicesOpenFileRef: ( FSRef * )fileref
	    withApplicationRef: ( FSRef * )appref
	    passThruParams: ( AERecord * )params
	    launchFlags: ( LSLaunchFlags )flags;
	    
- ( BOOL )launchServicesFindApplicationForCreatorType: ( OSType )creator
	bundleID: ( CFStringRef )bundleID
	appName: ( CFStringRef )appName
	foundAppRef: ( FSRef * )foundRef
	foundAppURL: ( CFURLRef * )appURL;
	
- ( BOOL )launchServicesFindApplication: ( CFStringRef )appName
	foundAppRef: ( FSRef * )foundRef;
        
- ( BOOL )launchServicesFindApplicationWithCreatorType: ( OSType )creator
        foundAppRef: ( FSRef * )foundRef;
        
- ( BOOL )launchServicesFindApplicationWithBundleID: ( CFStringRef )bundleID
        foundAppURL: ( CFURLRef * )foundURL;

@end
