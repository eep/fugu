/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "NSWorkspace(SystemVersionNumber).h"

@implementation NSWorkspace(SystemVersionNumber)

+ ( SInt32 )systemVersion
{
    SInt32		version;
    
    Gestalt( gestaltSystemVersion, &version );
    
    return( version );
}

@end
