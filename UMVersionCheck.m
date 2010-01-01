/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "UMVersionCheck.h"

#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>

#include <sys/param.h>

@implementation UMVersionCheck

/* needs to be multithreaded */
- ( NSDictionary * )retrieveVersionDictionary
{
    int                 rr;
    unsigned char       buf[ MAXPATHLEN * 2 ] = { 0 };
    NSURL				*versionPlistURL = [ NSURL URLWithString: VERSION_URL ];
    NSMutableData       *httpData = nil;
    NSDictionary        *versionPlist = nil;
    CFStringRef         request = CFSTR( "GET" ), errorString;
    CFHTTPMessageRef    httpMessage = NULL;
    CFReadStreamRef     readStream = NULL;
    
    /* create the http request */
    if (( httpMessage = CFHTTPMessageCreateRequest( kCFAllocatorDefault,
                request, ( CFURLRef )versionPlistURL, kCFHTTPVersion1_1 )) == NULL ) {
        NSLog( @"CFHTTPMessageCreateRequest failed." );
        return( nil );
    }
    
    /* create the readstream for the request */
    if (( readStream = CFReadStreamCreateForHTTPRequest( kCFAllocatorDefault,
                                            httpMessage )) == NULL ) {
        NSLog( @"CFReadStreamCreateForHTTPRequest failed." );
        return( nil );
    }
    
    /* auto-redirect */
    CFReadStreamSetProperty( readStream,
        kCFStreamPropertyHTTPShouldAutoredirect, kCFBooleanTrue );
        
    /* open connection */
    if ( CFReadStreamOpen( readStream ) == false ) {
        NSLog( @"CFReadStreamOpen failed." );
        return( nil );
    }
    
    for ( ;; ) {
        if ( ! CFReadStreamHasBytesAvailable( readStream )) {
            continue;
        }
    
        rr = CFReadStreamRead( readStream, buf, MAXPATHLEN * 2 );
        
        if ( rr <= 0 ) {
            break;
        }
        
        if ( httpData == nil ) {
            httpData = [[ NSMutableData alloc ] init ];
        }
        
        [ httpData appendBytes: buf length: rr ];
        
        if ( CFReadStreamGetStatus( readStream ) == kCFStreamStatusAtEnd ) {
            break;
        }
        
        memset( buf, '\0', sizeof( buf ));
    }
    
    CFReadStreamClose( readStream );
    
    if ( httpData == nil ) {
        NSLog( @"Failed to retrieve data from URL" );
        return( nil );
    }
    
    if (( versionPlist = ( id )CFPropertyListCreateFromXMLData( kCFAllocatorDefault,
                ( CFDataRef )httpData, kCFPropertyListImmutable, &errorString )) == NULL ) {
        NSLog( @"Failed to convert data to property list: %@", errorString );
    }
    
    [ httpData release ];
    
    if ( versionPlist ) {
        [ versionPlist autorelease ];
    }
    
    return( versionPlist );
}

- ( void )checkForUpdates
{
    NSDictionary        *versionDictionary = nil;
    NSDictionary	*infoPlist = nil;
    int			rc = 0;
    double              version = 0, current_version = 0;
    
    if (( versionDictionary = [ self retrieveVersionDictionary ] ) == nil ) {
        NSRunAlertPanel( NSLocalizedString( @"An error occurred checking for updates.",
                                            @"An error occurred checking for updates." ),
                        NSLocalizedString( @"Please check to make sure that you are connected "
                                            @"to the internet. If you are connected, and the "
                                            @"problem persists, please contact the authors of Fugu.",
                                            @"Please check to make sure that you are connected "
                                            @"to the internet. If you are connected, and the "
                                            @"problem persists, please contact the authors of Fugu." ),
                        NSLocalizedString( @"OK", @"OK" ), @"", @"" );
        return;
    }
    
    if (( infoPlist = [[ NSBundle mainBundle ] infoDictionary ] ) == nil ) {
	NSRunAlertPanel( @"Failed to locate Info.plist", @"",
					    NSLocalizedString( @"OK", @"OK" ),
					    @"", @"" );
	return;
    }
    current_version = [[ infoPlist objectForKey: @"UMVersionNumber" ] doubleValue ];

    if (( version = [[ versionDictionary objectForKey:
                        @"UMApplicationVersion" ] doubleValue ] ) <= current_version ) {
        NSRunAlertPanel( [ NSString stringWithFormat:
                                NSLocalizedString( @"You have the current version of %@.",
                                                    @"You have the current version of %@." ),
                                [ versionDictionary objectForKey: @"UMApplicationName" ]],
                @"", NSLocalizedString( @"OK", @"OK" ), @"", @"" );
        return;
    }
        
    
    rc = NSRunAlertPanel( [ NSString stringWithFormat:
                                NSLocalizedString( @"A new version of %@ is now available.",
                                            @"A new version of %@ is now available." ),
                                [ versionDictionary objectForKey: @"UMApplicationName" ]],
                NSLocalizedString( @"The latest version of %@ is %@. Click \"More Info\" "
                                        @"to open a web page about the new release. Click "
                                        @"\"Download\" to download the new version immediately.",
                                    @"The latest version of %@ is %@. Click \"More Info\" "
                                        @"to open a web page about the new release. Click "
                                        @"\"Download\" to download the new version immediately." ),
                NSLocalizedString( @"More Info...", @"More Info..." ),
                NSLocalizedString( @"Download", @"Download" ),
                NSLocalizedString( @"Later", @"Later" ),
                [ versionDictionary objectForKey: @"UMApplicationName" ],
                [ versionDictionary objectForKey: @"UMApplicationDisplayVersion" ] );
                
    switch ( rc ) {
    case NSAlertDefaultReturn:
        [[ NSWorkspace sharedWorkspace ] openURL:
                [ NSURL URLWithString:
                [ versionDictionary objectForKey:
                    @"UMApplicationInformationURL" ]]];
        break;
    case NSAlertAlternateReturn:
        [[ NSWorkspace sharedWorkspace ] openURL:
                [ NSURL URLWithString:
                [ versionDictionary objectForKey:
                    @"UMApplicationDirectDownloadURL" ]]];
        break;
    default:
        break;
    }
}

@end
