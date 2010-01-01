/*
 * Copyright (c) 2004 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Cocoa/Cocoa.h>

#define VERSION_URL			@"http://rsug.itd.umich.edu/software/fugu/version.plist"

@interface UMVersionCheck : NSObject
{
}

- ( NSDictionary * )retrieveVersionDictionary;
- ( void )checkForUpdates;

@end
