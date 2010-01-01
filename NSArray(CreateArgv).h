/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Foundation/Foundation.h>

@interface NSArray(CreateArgv)
- ( int )createArgv: ( char *** )argv;
@end
