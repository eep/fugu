/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "NSCalendarDate(ConvertToSeconds).h"

@implementation NSCalendarDate(ConvertToSeconds)

+ ( off_t )secondsFromFormattedDateString: ( NSString * )dString
{
    int			mo, curmo, day, yr, hr = 0, min = 0;
    NSCalendarDate	*d = nil;
    off_t		secs;
    NSArray		*a = [ dString componentsSeparatedByString: @" " ];
    NSDictionary	*months = [ NSDictionary dictionaryWithObjectsAndKeys:
                                    [ NSNumber numberWithInt: 1 ], @"jan",
                                    [ NSNumber numberWithInt: 2 ], @"feb",
                                    [ NSNumber numberWithInt: 3 ], @"mar",
                                    [ NSNumber numberWithInt: 4 ], @"apr",
                                    [ NSNumber numberWithInt: 5 ], @"may",
                                    [ NSNumber numberWithInt: 6 ], @"jun",
                                    [ NSNumber numberWithInt: 7 ], @"jul",
                                    [ NSNumber numberWithInt: 8 ], @"aug",
                                    [ NSNumber numberWithInt: 9 ], @"sep",
                                    [ NSNumber numberWithInt: 10 ], @"oct",
                                    [ NSNumber numberWithInt: 11 ], @"nov",
                                    [ NSNumber numberWithInt: 12 ], @"dec", nil ];
    
    
    mo = [[ months objectForKey: [[ a objectAtIndex: 0 ]
                    lowercaseString ]] intValue ];
                    
    day = [[ a objectAtIndex: 1 ] intValue ];
    
    if ( strchr( [[ a objectAtIndex: 2 ] UTF8String ], ':' ) == NULL ) {
        yr = [[ a objectAtIndex: 2 ] intValue ];
    } else {
        NSArray		*b = [[ a objectAtIndex: 2 ]
                                    componentsSeparatedByString: @":" ];
                                    
        hr = [[ b objectAtIndex: 0 ] intValue ];
        min = [[ b objectAtIndex: 1 ] intValue ];
        
        if ( [ a count ] == 4 ) {
            yr = [[ a objectAtIndex: 3 ] intValue ];
        } else {    /* modified/created within last six months */
            curmo = [[[ NSDate date ] descriptionWithCalendarFormat: @"%m"
                                    timeZone: [ NSTimeZone defaultTimeZone ]
                                    locale: nil ] intValue ];
            yr = [[[ NSDate date ] descriptionWithCalendarFormat: @"%Y"
                                    timeZone: [ NSTimeZone defaultTimeZone ]
                                    locale: nil ] intValue ];

            /* compensate for year rollover */
            if ( mo > 6 && ( curmo >= 1 && curmo < 6 )) {
                yr--;
            }
        }
    }
    
    d = [[[ NSCalendarDate alloc ] initWithYear: yr month: mo day: day
                            hour: hr minute: min second: 0
                            timeZone: nil ] autorelease ];
                            
    secs = [ d timeIntervalSince1970 ];
    
    return( secs );
}

@end
