/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */
 
 /*
  * Icon caching category for NSImage.
  * Should really be NSImage(Icon)
  */

#import "NSImage(IconForType).h"
#include <sys/types.h>
#include <sys/stat.h>

static NSMutableDictionary      *cachedIconDictionary = nil;

@implementation NSImage(IconForType)

+ ( NSImage * )iconForType: ( NSString * )extension
{
    static NSMutableDictionary	*images = nil;
    NSImage			*icon = nil;
    NSString			*ext = extension;
    
    if ( extension == nil ) {
        return( nil );
    }
    
    if ( [ ext isEqualToString: @"" ] ) {
        ext = @"'doc '";
    }
    
    if ( images == nil ) {
        images = [[ NSMutableDictionary alloc ] init ];
    }
    
    if (( icon = [ images objectForKey: ext ] ) == nil ) {
        if (( icon = [[ NSWorkspace sharedWorkspace ] iconForFileType: ext ] ) != nil ) {
            [ images setObject: icon forKey: ext ];
        }
    }
    
    return( icon );
}

+ ( NSImage * )iconForFile: ( NSString * )file
{
    NSMutableDictionary         *icons = nil;
    NSImage			*icon = nil;
    NSString                    *parent = nil;
    
    if ( file == nil || [ file length ] == 0 ) {
        return( nil );
    }
    
    parent = [ file stringByDeletingLastPathComponent ];
    
    if (( icons = [ cachedIconDictionary objectForKey: parent ] ) == nil ) {
        return( [ NSImage iconForType: file ] );
    }
    if (( icon = [ icons objectForKey: file ] ) == nil ) {
        return( [ NSImage iconForType: file ] );
    }
    
    return( icon );
}

+ ( void )cacheIconsForPath: ( NSString * )path contents: ( NSArray * )items
{
    NSArray                     *a = items, *reps;
    NSAutoreleasePool           *pool = nil;
    NSMutableDictionary         *icons = nil;
    NSImage                     *icon = nil;
    NSDate                      *stamp = nil;
    NSString                    *file = nil;
    NSTimeInterval              t, s;
    struct stat			st;
    int                         i, j;
    
    if ( path == nil || [ path length ] == 0 || a == nil || [ a count ] == 0 ) {
        return;
    }
    
    if (( icons = [ cachedIconDictionary objectForKey: path ] ) != nil ) {
        /* we've already cached the icons at path. see if they're out of date */
	if ( stat( [ path UTF8String ], &st ) < 0 ) {
	    /* we'll encounter this error and handle it better if SFTPNode */
	    return;
	}
        stamp = [ icons objectForKey: @"CacheTimestamp" ];
        t = [ stamp timeIntervalSince1970 ];
        s = [[ NSDate date ] timeIntervalSince1970 ];
        if (( s - t ) < 10800 && t > st.st_mtime ) {
            return;
        }
        
        /* if it's too old, delete it */
        icons = nil;
        [ cachedIconDictionary removeObjectForKey: path ];
    }
    
    icons = [[ NSMutableDictionary alloc ] init ];
    
    pool = [[ NSAutoreleasePool alloc ] init ];
    for ( i = 0; i < [ a count ]; i++ ) {
        file = [ path stringByAppendingPathComponent: [ a objectAtIndex: i ]];

        if (( icon = [[ NSWorkspace sharedWorkspace ] iconForFile: file ] ) != nil ) {
            /* only cache 16x16 icons */
            reps = [[ icon representations ] retain ];
            for ( j = 0; j < [ reps count ]; j++ ) {
                if ( [[ reps objectAtIndex: j ] pixelsHigh ] != 16 ) {
                    if ( [[ icon representations ] count ] > 1 ) {
                        [ icon removeRepresentation: [ reps objectAtIndex: j ]];
                    }
                }
            }
            [ reps release ];
            
            [ icon setScalesWhenResized: YES ];
            [ icon setSize: NSMakeSize( 16.0, 16.0 ) ];
            [ icons setObject: icon forKey: file ];
        }
    }
    [ pool release ];
    
    if ( !cachedIconDictionary ) {
        cachedIconDictionary = [[ NSMutableDictionary alloc ] init ];
    }
    
    if ( [ cachedIconDictionary count ] >= 5 ) {
        a = [ cachedIconDictionary
                keysSortedByValueUsingSelector: @selector( cacheDateCompare: ) ];
        [ cachedIconDictionary removeObjectForKey: [ a lastObject ]];
    }
    
    [ icons setObject: [ NSDate date ] forKey: @"CacheTimestamp" ];
    [ cachedIconDictionary setObject: icons forKey: path ];
    [ icons release ];
}

@end
