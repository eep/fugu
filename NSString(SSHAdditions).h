/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */
 
#import <Foundation/Foundation.h>

#define LOCALSTR(x)	    NSLocalizedString((x), (x))

@interface NSString(SSHAdditions)

+ ( NSDictionary * )unknownHostInfoFromString: ( NSString * )string;
+ ( NSString * )pathFromBaseDir: ( NSString * )base fullPath: ( NSString * )fullpath;
+ ( NSString * )clockStringFromInteger: ( int )integer;
+ ( NSString * )pathForExecutable: ( NSString * )executable;
- ( NSString * )octalRepresentation;
- ( char )objectTypeFromOctalRepresentation: ( NSString * )octalRep;
- ( NSString * )stringRepresentationOfOctalMode;
- ( BOOL )containsString: ( NSString * )substring caseInsensitiveComparison: ( BOOL )cmp;
- ( BOOL )containsString: ( NSString * )substring;
- ( BOOL )beginsWithString: ( NSString * )substring;
- ( Str255 * )pascalString;
- ( NSString * )stringByExpandingTildeInRemotePathWithHomeSetAs: ( NSString * )remoteHome;
- ( NSString * )descriptiveSizeString;
- ( NSString * )escapedPathString;

@end
