/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "NSWorkspace(LaunchServices).h"

#include <sys/types.h>
#include <sys/param.h>

@implementation NSWorkspace(LaunchServices)

/* corresponds to LSOpenFromURLSpec() */
- ( BOOL )launchServicesOpenFileRef: ( FSRef * )fileref
	    withApplicationRef: ( FSRef * )appref
	    passThruParams: ( AERecord * )params
	    launchFlags: ( LSLaunchFlags )flags
{
    LSLaunchURLSpec	lspec = { NULL, NULL, NULL, 0, NULL };
    BOOL		success = YES;
    OSStatus		status;
    CFURLRef		fileurl = NULL, appurl = NULL;
    CFArrayRef		arrayref = NULL;
    
    if ( fileref != NULL ) {
	if (( fileurl = CFURLCreateFromFSRef( kCFAllocatorDefault, fileref )) == NULL ) {
	    NSLog( @"CFURLCreateFromFSRef failed." );
	    return( NO );
	}
	if (( arrayref = CFArrayCreate( kCFAllocatorDefault,
		    ( const void ** )&fileurl, 1, NULL )) == NULL ) {
	    NSLog( @"CFArrayCreate failed." );
	    return( NO );
	}
    }
    
    if ( appref != NULL ) {
	if (( appurl = CFURLCreateFromFSRef( kCFAllocatorDefault, appref )) == NULL ) {
	    NSLog( @"CFURLCreateFromFSRef failed." );
	    return( NO );
	}
    }

    lspec.appURL = appurl;
    lspec.itemURLs = arrayref;
    lspec.passThruParams = params;
    lspec.launchFlags = flags;
    lspec.asyncRefCon = NULL;
    
    status = LSOpenFromURLSpec( &lspec, NULL );
    
    if ( status != noErr ) {
	NSLog( @"LSOpenFromRefSpec failed: error %d", status );
	success = NO;
    }
    
    if ( appurl != NULL ) {
	CFRelease( appurl );
    }
    if ( fileurl != NULL ) {
	CFRelease( fileurl );
    }
    if ( arrayref != NULL ) {
	CFRelease( arrayref );
    }
    
    return( success );
}

/* corresponds to LSFindApplicationForInfo() */
- ( BOOL )launchServicesFindApplicationForCreatorType: ( OSType )creator
	bundleID: ( CFStringRef )bundleID
	appName: ( CFStringRef )appName
	foundAppRef: ( FSRef * )foundRef
	foundAppURL: ( CFURLRef * )appURL
{
    OSStatus		status;
    BOOL		success = YES;
    NSString            *modifiedAppName = nil;
    
    /* start by looking for bundleID and appName */
    if (( status = LSFindApplicationForInfo( kLSUnknownCreator,
                                            bundleID, appName,
                                            foundRef, appURL )) == noErr ) {
        return( success );
    }
    
    /*
     * try just bundleID. seems to resolve problems looking
     * for PPC (Rosetta) applications on Intel Macs.
     */
    if (( status = LSFindApplicationForInfo( kLSUnknownCreator,
					    bundleID, NULL,
					    foundRef, appURL )) == noErr ) {
	return( success );
    }
    
    /* then try application name only */
    if (( status = LSFindApplicationForInfo( kLSUnknownCreator,
                                            NULL, appName,
                                            foundRef, appURL )) != noErr ) {
        if ( appName != NULL ) {
            if ( [[ ( NSString * )appName pathExtension ] isEqualToString: @"" ] ) {
                modifiedAppName = [ ( NSString * )appName stringByAppendingPathExtension: @"app" ];
            } else {
                modifiedAppName = [ ( NSString * )appName stringByDeletingPathExtension ];
            }
            
            status = LSFindApplicationForInfo( creator, bundleID,
                                    ( CFStringRef )modifiedAppName, foundRef, appURL );
            
            if ( status == noErr ) {
                return( success );
            }
        } else if ( creator != kLSUnknownCreator ) {
            /* finally, try searching by creator code */
            status = LSFindApplicationForInfo( creator, NULL, NULL, foundRef, appURL );
            if ( status == noErr ) {
                return( success );
            }
        }
#ifdef DEBUG
	NSLog( @"Couldn't find application %@: error %d", ( NSString * )appName, status );
#endif /* DEBUG */
	success = NO;
    }
    
    return( success );
}

/* limited version of the above */
- ( BOOL )launchServicesFindApplication: ( CFStringRef )appName
	foundAppRef: ( FSRef * )foundRef
{
    return( [ self launchServicesFindApplicationForCreatorType: kLSUnknownCreator
		    bundleID: NULL appName: appName
		    foundAppRef: foundRef foundAppURL: NULL ] );
}

- ( BOOL )launchServicesFindApplicationWithCreatorType: ( OSType )creator
        foundAppRef: ( FSRef * )foundRef
{
    return( [ self launchServicesFindApplicationForCreatorType: creator
		    bundleID: NULL appName: NULL
		    foundAppRef: foundRef foundAppURL: NULL ] );
}

- ( BOOL )launchServicesFindApplicationWithBundleID: ( CFStringRef )bundleID
        foundAppURL: ( CFURLRef * )foundURL
{
    return( [ self launchServicesFindApplicationForCreatorType: '????'
                    bundleID: bundleID appName: NULL
                    foundAppRef: NULL foundAppURL: foundURL ] );
}

@end
