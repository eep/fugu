/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Cocoa/Cocoa.h>

@interface NSImage(IconForType)

+ ( NSImage * )iconForType: ( NSString * )extension;
+ ( NSImage * )iconForFile: ( NSString * )file;
+ ( void )cacheIconsForPath: ( NSString * )path contents: ( NSArray * )items;

@end
