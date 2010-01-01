/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "NSFileManager(mktemp).h"

#include <sys/types.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <errno.h>
#include <unistd.h>

@implementation NSFileManager(mktemp)

- ( NSString * )makeTemporaryDirectoryWithMode: ( mode_t )mode
{
    char	template[ MAXPATHLEN ] = "/private/tmp/Fugu/tmp.XXXXXX";
    
    if ( mkdir( C_TMPFUGUDIR, mode ) < 0 ) {
	if ( errno != EEXIST ) {
	    return( nil );
	}
    }
    if ( mkdtemp( template ) == NULL ) {
	if ( errno != EEXIST ) {
	    return( nil );
	}
    }
    
    return( [ NSString stringWithUTF8String: template ] );
}

@end
