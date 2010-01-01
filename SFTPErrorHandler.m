/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Foundation/Foundation.h>
#import "SFTPErrorHandler.h"

@implementation SFTPErrorHandler

- ( void )runErrorPanel: ( NSString * )theError
{
    NSRunAlertPanel( @"Error", theError, @"OK", @"", @"" );
}

- ( void )fatalErrorPanel: ( NSString * )fatalError
{
    NSRunAlertPanel( @"Fatal Error", fatalError, @"Quit", @"", @"" );
    exit( 2 );
}

@end
