/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "UMFileLauncher.h"
#include <sys/types.h>
#include <errno.h>
#include <unistd.h>

extern int			errno;

@implementation UMFileLauncher

- ( BOOL )openFile: ( NSString * )file withApplication: ( NSString * )app
{
    if ( app == nil ) {
        if ( ! [[ NSWorkspace sharedWorkspace ] openFile: file ] ) return( NO );
        return( YES );
    }
    
    return( NO );
}

- ( BOOL )externalEditFile: ( NSString * )path
            withCLIEditor: ( NSString * )editor
            contextInfo: ( void * )contextInfo
{
    NSAppleScript               *as = nil;
    NSDictionary                *errorDictionary = nil;
    NSString                    *scriptSource = nil;
    NSString                    *exed = [[ NSBundle mainBundle ] pathForResource:
                                            @"externaleditor" ofType: nil ];
                                            
    if ( exed == nil ) {
        NSLog( @"externaleditor not found!" );
        return( NO );
    }

    scriptSource = [ NSString stringWithFormat:
			@"tell application \"Terminal\"\r"
			    @"activate\r"
			    @"do script \"%@ %@ \\\"%@\\\" \\\"%@\\\"; exit\"\r"
			@"end tell", exed, editor, path, ( NSString * )contextInfo ];
    
    as = [[ NSAppleScript alloc ] initWithSource: scriptSource ];
    if ( [ as executeAndReturnError: &errorDictionary ] == nil ) {
        NSLog( @"Failed to open terminal with AppleScript: %@",
                [ errorDictionary objectForKey: @"NSAppleScriptErrorMessage" ] );
        [ as release ];
        return( NO );
    }
    
    [ as release ];
    return( YES );
}

@end
