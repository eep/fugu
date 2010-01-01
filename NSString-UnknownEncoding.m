/*
 * Copyright (c) 2004 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */
 
#import "NSString-UnknownEncoding.h"

#include <CoreFoundation/CoreFoundation.h>

@implementation NSString(UnknownEncoding)

/* external encodings to be used if internal CFString.h encoding conversion failed */
+ ( NSString * )stringWithBytesOfUnknownExternalEncoding: ( char * )bytes
                length: ( unsigned )len
{
    int                     i, enccount = 0;
    CFStringRef             convertedString = NULL;
    CFStringEncoding        encodings[] = { kCFStringEncodingISOLatin2,
                                                kCFStringEncodingISOLatin3,
                                                kCFStringEncodingISOLatin4,
                                                kCFStringEncodingISOLatinCyrillic,
                                                kCFStringEncodingISOLatinArabic,
                                                kCFStringEncodingISOLatinGreek,
                                                kCFStringEncodingISOLatinHebrew,
                                                kCFStringEncodingISOLatin5,
                                                kCFStringEncodingISOLatin6,
                                                kCFStringEncodingISOLatinThai,
                                                kCFStringEncodingISOLatin7,
                                                kCFStringEncodingISOLatin8,
                                                kCFStringEncodingISOLatin9,
                                                kCFStringEncodingWindowsLatin2,
                                                kCFStringEncodingWindowsCyrillic,
                                                kCFStringEncodingWindowsGreek,
                                                kCFStringEncodingWindowsLatin5,
                                                kCFStringEncodingWindowsHebrew,
                                                kCFStringEncodingWindowsArabic,
                                                kCFStringEncodingKOI8_R,
                                                kCFStringEncodingBig5,
                                                kCFStringEncodingNextStepLatin };
                                                
    if ( bytes == NULL ) {
        return( nil );
    }
    
    enccount = ( sizeof( encodings ) / sizeof( CFStringEncoding ));
    
    for ( i = 0; i < enccount; i++) {
        if ( ! CFStringIsEncodingAvailable( encodings[ i ] )) {
            continue;
        }
        
        if (( convertedString = CFStringCreateWithBytes( kCFAllocatorDefault,
                        ( UInt8 * )bytes, len, encodings[ i ], true )) != NULL ) {
            break;
        }
    }

    return(( NSString * )convertedString );
}

+ ( NSString * )stringWithBytesOfUnknownEncoding: ( char * )bytes
                length: ( unsigned )len
{
    int                     i, enccount = 0;
    CFStringRef             convertedString = NULL;
    CFStringEncoding        encodings[] = { kCFStringEncodingUTF8,
                                                kCFStringEncodingISOLatin1,
                                                kCFStringEncodingWindowsLatin1,
                                                kCFStringEncodingNextStepLatin };
    
    if ( bytes == NULL ) {
        return( nil );
    }
    
    enccount = ( sizeof( encodings ) / sizeof( CFStringEncoding ));
    
    for ( i = 0; i < enccount; i++) {
        if (( convertedString = CFStringCreateWithBytes( kCFAllocatorDefault,
                        ( UInt8 * )bytes, len, encodings[ i ], false )) != NULL ) {
            break;
        }
    }

    if ( convertedString == NULL ) {
        convertedString = ( CFStringRef )[ NSString stringWithBytesOfUnknownExternalEncoding: bytes
                                            length: len ];
    }
    
    if ( convertedString != NULL ) {
        [ ( NSString * )convertedString autorelease ];
    }
                                    
    return(( NSString * )convertedString );
}

@end
