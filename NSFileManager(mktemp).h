/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <AppKit/AppKit.h>

#define C_TMPFUGUDIR		"/private/tmp/Fugu"
#define OBJC_TMPFUGUDIR 	@"/private/tmp/Fugu"

@interface NSFileManager(mktemp)

- ( NSString * )makeTemporaryDirectoryWithMode: ( mode_t )mode;

@end
