/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SFTPMainWindow.h"
#import "SFTPController.h"

#include <unistd.h>
#include <sys/param.h>

@implementation SFTPMainWindow

- ( int )setTitleToLocalHostName
{
    char	host[ MAXHOSTNAMELEN ];
    
    if ( gethostname( host, MAXHOSTNAMELEN ) < 0 ) {
        [ self setTitle: NSLocalizedString( @"localhost: disconnected", @"localhost: disconnected" ) ];
        return( -1 );
    } else {
        [ self setTitle: [ NSString stringWithFormat:
			NSLocalizedString( @"%@ (localhost): disconnected",
				@"%@ (localhost): disconnected" ),
                        [ NSString stringWithUTF8String: host ]]];
        return( 0 );
    }
}
@end
