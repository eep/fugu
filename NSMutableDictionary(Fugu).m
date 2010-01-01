/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "NSMutableDictionary(Fugu).h"


@implementation NSMutableDictionary(Fugu)

+ ( NSMutableDictionary * )favoriteDictionaryFromHostname: ( NSString * )hostname
{
    return( [ NSMutableDictionary dictionaryWithObjectsAndKeys:
                                @"", @"nick",
                                hostname, @"host",
                                @"", @"user",
                                @"", @"port",
                                @"", @"dir", nil ] );
}

- ( NSComparisonResult )cacheDateCompare: ( NSDictionary * )dict
{
    return( [ (NSDate*)[ dict objectForKey: @"CacheTimestamp" ] compare:
                        [ self objectForKey: @"CacheTimestamp" ]] );
}

@end
