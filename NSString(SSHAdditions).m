/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "NSString(SSHAdditions).h"
#import "NSString-UnknownEncoding.h"
#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>

#include <sys/types.h>
#include <sys/param.h>
#include <stdlib.h>

@implementation NSString(SSHAdditions)

+ ( NSDictionary * )unknownHostInfoFromString: ( NSString * )string
{
    NSString 	*allUnknownHostInfo = nil;
    NSString 	*notKnownMessage = nil;
    char 	*unknownkey;
    
    [[ NSScanner scannerWithString: string ] scanUpToString: @"Are"
                intoString: &allUnknownHostInfo ];
    
    [[ NSScanner scannerWithString: allUnknownHostInfo ] scanUpToString: @"DSA"
                intoString: &notKnownMessage ];
                
    if ( [ notKnownMessage isEqualToString: allUnknownHostInfo ] ) {
        [[ NSScanner scannerWithString: allUnknownHostInfo ] scanUpToString: @"RSA"
                intoString: &notKnownMessage ];
    }
    
    if (( unknownkey = strstr( [ allUnknownHostInfo UTF8String ], "RSA" )) == NULL ) {
        if (( unknownkey = strstr( [ allUnknownHostInfo UTF8String ], "DSA" )) == NULL ) {
            NSLog( @"Couldn't get unknown host key." );
            unknownkey = "Unable to get host key. Something is odd.";
        }
    }
    
    return( [ NSDictionary dictionaryWithObjectsAndKeys:
                notKnownMessage, @"msg",
                [ NSString stringWithUTF8String: unknownkey ], @"key", NULL ] );
}

+ ( NSString * )pathFromBaseDir: ( NSString * )base fullPath: ( NSString * )fullpath
{
    NSRange	r;
    NSString	*basename;
    NSString	*tmp;

    if ( fullpath == nil ) return( nil );
    
    basename = [ base lastPathComponent ];
    tmp = [ base stringByDeletingLastPathComponent ];
    
    r = [ fullpath rangeOfString: basename ];
    if ( r.location == NSNotFound ) {
        return( basename );
    }
    
    return( [ NSString stringWithFormat: @"%@/%@", tmp, [ fullpath substringFromIndex: r.location ]] );
}

+ ( NSString * )clockStringFromInteger: ( int )integer
{
    int			secs, mins, hrs;
    
    hrs = (( integer / 60 ) / 60 );
    mins = (( integer / 60 ) % 60 );
    secs = (( integer % 60 ) % 60 );
    
    return( [ NSString stringWithFormat: @"%.2d:%.2d:%.2d", hrs, mins, secs ] );
}

+ ( NSString * )pathForExecutable: ( NSString * )executable
{
    NSString	*executablePath = nil;
    NSString	*searchPath = [[ NSUserDefaults standardUserDefaults ]
				objectForKey: @"ExecutableSearchPath" ];

    if ( searchPath == nil ) {
	searchPath = @"/usr/bin";
    }

    executablePath = [ searchPath stringByAppendingPathComponent: executable ];

    if ( [[ NSFileManager defaultManager ]
			fileExistsAtPath: executablePath ] ) {
	char	*env_path;
	char	new_env[ MAXPATHLEN * 2 ];

	/* let sftp and ssh know about the additional path, too */
	if (( env_path = getenv( "PATH" )) != NULL ) {
	    if ( snprintf( new_env, MAXPATHLEN * 2, "%s:%s",
				[ searchPath UTF8String ],
				env_path ) < MAXPATHLEN * 2 ) {
		if ( setenv( "PATH", new_env, 1 ) != 0 ) {
		    NSLog( @"Failed to set PATH to %s\n", new_env );
		}
	    } else {
		NSLog( @"%@:%s is too long", searchPath, env_path );
	    }
	}
	return( executablePath );
    }

    /* try again with a default path */
    executablePath = nil;
    executablePath = [ NSString stringWithFormat: @"/usr/bin/%@", executable ];

    if ( ! [[ NSFileManager defaultManager ]
		fileExistsAtPath: executablePath ] ) {
        executablePath = nil;
    }

    return( executablePath );
}

- ( NSString * )octalRepresentation
{
    char	*p = ( char * )[ self UTF8String ];
    int		i, oow = 0, ogr = 0, oot = 0, s = 0;
    
    for ( i = 0, p++; *p != '\0'; i++, p++ ) {
        switch ( *p ) {
        case 'r':
            if ( i < 3 ) oow += 4;
            if ( i >=3 && i < 6 ) ogr += 4;
            if ( i >=6 && i < 9 ) oot += 4;
            break;
        case 'w':
            if ( i < 3 ) oow += 2;
            if ( i >=3 && i < 6 ) ogr += 2;
            if ( i >=6 && i < 9 ) oot += 2;
            break;
        case 'x':
            if ( i < 3 ) oow += 1;
            if ( i >=3 && i < 6 ) ogr += 1;
            if ( i >=6 && i < 9 ) oot += 1;
            break;
        case 's':
            if ( i < 3 ) { s += 4; oow += 1; }
            if ( i >= 3 && i < 6 ) { s += 2; ogr += 1; }
            break;
        case 't':
            s += 1;
            oot += 1;
        }
    }
    
    return( [ NSString stringWithFormat: @"%d%d%d%d", s, oow, ogr, oot ] );
}

- ( NSString * )stringRepresentationOfOctalMode
{
    NSString	*type = nil;
    char	tmp[ 11 ] = "----------";
    int		i = 1, j = 0, len = [ self length ];
    
    /*
     * if we're dealing with a server that outputs modes and types
     * as an octal string, start creating the mode string from
     * the appropriate point
     */
    if ( len == 6 ) {
        i = 3;
    } else if ( len == 7 ) {
        i = 4;
    } else {
        i = 1;
    }

    for ( j = 1; i < len; i++, j += 3 ) {
        switch( [ self characterAtIndex: i ] ) {
        case '0':
            break;
        case '1':
            tmp[ j + 2 ] = 'x';
            break;
        case '2':
            tmp[ j + 1 ] = 'w';
            break;
        case '3':
            tmp[ j + 1 ] = 'w';
            tmp[ j + 2 ] = 'x';
            break;
        case '4':
            tmp[ j ] = 'r';
            break;
        case '5':
            tmp[ j ] = 'r';
            tmp[ j + 2 ] = 'x';
            break;
        case '6':
            tmp[ j ] = 'r';
            tmp[ j + 1 ] = 'w';
            break;
        case '7':
            tmp[ j ] = 'r';
            tmp[ j + 1 ] = 'w';
            tmp[ j + 2 ] = 'x';
            break;
        }
    }
    
    if ( len == 6 ) {
        i = 3;
    } else if ( len == 7 ) {
        i = 4;
    } else {
        i = 1;
    }
    
    switch( [ self characterAtIndex: ( i - 1 ) ] ) {
    case '0':
        break;
    case '1':
        /* sticky bit */
        tmp[ 9 ] = 't';
        break;
    case '2':
        /* setgid */
        if ( tmp[ 6 ] != 'x' ) {
            tmp[ 6 ] = 'S';
        } else {
            tmp[ 6 ] = 's';
        }
        
        break;
    case '4':
        /* setuid */
        if ( tmp[ 3 ] != 'x' ) {
            tmp[ 3 ] = 'S';
        } else {
            tmp[ 3 ] = 's';
        }
        
        break;
    }
    
    if ( len == 6 ) {
        type = [ self substringToIndex: 2 ];
        tmp[ 0 ] = [ self objectTypeFromOctalRepresentation: type ];
    } else if ( len == 7 ) {
        type = [ self substringToIndex: 3 ];
        tmp[ 0 ] = [ self objectTypeFromOctalRepresentation: type ];
    } else {
        tmp[ 0 ] = ' ';
    }

    return( [ NSString stringWithUTF8String: tmp ] );
}

- ( char )objectTypeFromOctalRepresentation: ( NSString * )octalRep
{
    if ( [ octalRep isEqualToString: @"01" ] ) return( 'p' );
    else if ( [ octalRep isEqualToString: @"02" ] ) return( 'c' );
    else if ( [ octalRep isEqualToString: @"04" ] ) return( 'd' );
    else if ( [ octalRep isEqualToString: @"06" ] ) return( 'b' );
    else if ( [ octalRep isEqualToString: @"010" ] ) return( '-' );
    else if ( [ octalRep isEqualToString: @"012" ] ) return( 'l' );
    else if ( [ octalRep isEqualToString: @"014" ] ) return( 's' );
    else if ( [ octalRep isEqualToString: @"016" ] ) return( 'D' );
    else return( '-' );
}

- ( BOOL )containsString: ( NSString * )substring caseInsensitiveComparison: ( BOOL )cmp
{
    unsigned			mask = NSLiteralSearch;
    
    if ( substring == nil || [ substring isEqualToString: @"" ] ) {
        return( NO );
    }
    
    if ( cmp == YES ) {
        mask = NSCaseInsensitiveSearch;
    }
    
    if ( [ self rangeOfString: substring options: mask ].location != NSNotFound ) {
        return( YES );
    }
    return( NO );
}

- ( BOOL )containsString: ( NSString * )substring
{
    return( [ self containsString: substring caseInsensitiveComparison: NO ] );
}

/* this is a case-insensitive comparison */
- ( BOOL )beginsWithString: ( NSString * )substring
{
    if ( substring == nil ) return( NO );
    
    if ( [ self rangeOfString: substring options: NSCaseInsensitiveSearch ].location == 0 ) {
        return( YES );
    }
    return( NO );
}

/* returns a malloc'd pascal string, which must be free'd after use */
- ( Str255 * )pascalString
{
    Str255		*ps;
    
    if ( self == nil ) return( NULL );
    
    if (( ps = malloc( sizeof( Str255 ))) == NULL ) return( NULL );
    
    if ( ! CFStringGetPascalString(( CFStringRef )self, *ps, sizeof( *ps ),
                                    CFStringGetSystemEncoding())) {
        free( ps );
        [ NSException raise: NSInternalInconsistencyException
                        format: @"Failed to convert NSString %@ to a pascal string.", self ];
    }
    return( ps );
}

- ( NSString * )stringByExpandingTildeInRemotePathWithHomeSetAs: ( NSString * )remoteHome
{
    NSString		*expandedString = nil;
    
    if ( [ self length ] == 0 || self == nil ) return( self );
    
    if ( [ self characterAtIndex: 0 ] == '~' ) {
        NSRange		tildeRange = [ self rangeOfString: @"~" ];
        unsigned int	len = [ self length ];
        
        if ( len > 1 ) {
            NSRange	slashRange = [ self rangeOfString: @"/" ];
            
            tildeRange.location += 1;
            
            if ( slashRange.location == NSNotFound ) {	/* ~username format */
                expandedString = [ NSString stringWithFormat: @"%@/%@",
                            [ remoteHome stringByDeletingLastPathComponent ],
                            [ self substringFromIndex: tildeRange.location ]];
            } else if ( slashRange.location > 1 ) { 	/* ~username/dirname format */
                int 	sublen = [[ self substringFromIndex: slashRange.location ] length ];
                expandedString = [ NSString stringWithFormat: @"%@/%@/%@",
                            [ remoteHome stringByDeletingLastPathComponent ],
                            [ self substringWithRange:
                                        NSMakeRange( tildeRange.location, ( len - sublen - 1 )) ],
                            [ self substringFromIndex: slashRange.location ]];
            } else if ( slashRange.location == 1 ) {	/* ~/dirname format */
                expandedString = [ NSString stringWithFormat: @"%@%@", remoteHome,
                                [ self substringFromIndex: tildeRange.location ]];
            }
        } else {
            expandedString = remoteHome;
        }
    } else {
        expandedString = self;
    }
    return( expandedString );
}

- ( NSString * )descriptiveSizeString
{
    const char			*s = [ self UTF8String ];
    off_t			size, m, n;
    float			fraction, mbytes;
    
    if (( size = strtoll( s, NULL, 10 )) == 0 ) {
        /* don't bother with an error, just return bytes */
        return( self );
    }
    
    /* if the size is less than 1K, return bytes */
    if (( m = ( size / 1024 )) == 0 ) {
        return( [ NSString stringWithFormat: @"%@ B  ", self ] );
    }
    
    /* if size is less than 1MB, return kbytes */
    if (( n = ( m / 1024 )) == 0 ) {
        /* round up, if necessary */
        if (( size % 1024 ) > 512 ) {
            m++;
        }
        return( [ NSString stringWithFormat: @"%lld KB  ", m ] );
    }
    
    /* otherwise, return in MB */
    m = ( m % 1024 );
    fraction = ( float )( m / 1024.0 );
    mbytes = ( float )n;
    mbytes += fraction;
    
    return( [ NSString stringWithFormat: @"%.2f MB  ", mbytes ] );
}

- ( NSString * )escapedPathString
{
    NSString                *escapedPath = nil;
    char                    *s = strdup( [ self UTF8String ] );
    char                    esc[ MAXPATHLEN ] = { 0 };
    int                     i, j;
    
    if ( s == NULL ) {
        NSLog( @"strdup: %s", strerror( errno ));
        exit( 2 );
    }
    
    for ( i = j = 0; j < strlen( s ); i++, j++ ) {
        if ( i >= MAXPATHLEN ) {
            NSLog( @"convert %s to an escaped path: too long", s );
            return( self );
        }
        
        switch ( s[ j ] ) {
        case '[' :
        case '\"':
        case '\'':
        case ' ' :
        case '\\':
            esc[ i ] = '\\';
            i++;
            break;
        }
        
        esc[ i ] = s[ j ];
    }
    
    if ( s ) {
        free( s );
    }
    
    escapedPath = [ NSString stringWithBytesOfUnknownEncoding: esc
                                length: strlen( esc ) ];
                                
    return( escapedPath );
}

@end
