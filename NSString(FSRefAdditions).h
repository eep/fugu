/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Foundation/Foundation.h>

#include <Carbon/Carbon.h>
#include <CoreServices/CoreServices.h>
#include <CoreFoundation/CoreFoundation.h>

@interface NSString(FSRefAdditions)
#ifdef notdef
- ( Str255 * )pascalString;
#endif /* notdef */

+ ( NSString * )stringWithFSRef: ( FSRef * )fsref;
+ ( NSString * )stringWithFSSpec: ( FSSpec * )fsspec;
+ ( NSString * )stringWithAlias: ( AliasHandle )alias;
- ( OSStatus )makeFSSpec: ( FSSpec * )spec;
- ( OSStatus )makeFSRefRepresentation: ( FSRef * )fsref;
- ( NSString * )stringByResolvingAliasInPath;
- ( BOOL )isAliasFile;

@end
