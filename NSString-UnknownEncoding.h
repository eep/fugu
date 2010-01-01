/*
 * Copyright (c) 2004 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Foundation/Foundation.h>

@interface NSString(UnknownEncoding)

+ ( NSString * )stringWithBytesOfUnknownEncoding: ( char * )bytes
                length: ( unsigned )len;

@end
