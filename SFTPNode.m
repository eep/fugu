/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SFTPNode.h"
#import "NSImage(IconForType).h"
#import "NSString(SSHAdditions).h"
#import "NSString(FSRefAdditions).h"

#include <sys/types.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <errno.h>
#include <grp.h>
#include <pwd.h>
#include <time.h>
#include <tzfile.h>
#include <unistd.h>

extern int		errno;

    time_t
sixmo_in_secs()
{
    return(( DAYSPERNYEAR / 2 ) * SECSPERDAY );
}

    time_t
now()
{
    return( time( NULL ));
}

@implementation SFTPNode

+ ( SFTPNode * )sharedInstance
{
    SFTPNode *sharedInstance = nil;
    
    if ( !sharedInstance ) {
        sharedInstance = [[ SFTPNode alloc ] init ];
    }
    
    return( [ sharedInstance autorelease ] );
}

- ( NSSet * )invisibles
{
    NSSet		*invisibles = [ NSSet setWithObjects: @"cores",
                                            @"sbin", @"resources",
                                            @"private", @"automount",
                                            @"etc", @"dev", @"tmp", @"var",
                                            @"bin", @"usr", @"mach_kernel",
                                            @"mach", @"mach.sym",
                                            @"Desktop DF", @"Desktop DB", nil ];
                                            
    return( invisibles );
}

- ( NSSet * )bundleExtensions
{
    NSSet		*bundleExtensions = [ NSSet setWithObjects: @"app",
                                                            @"mpkg", @"pkg",
                                                            @"nib", @"rtfd",
                                                            @"kext", nil ];
                                                
    return( bundleExtensions );
}

- ( BOOL )isDirectory: ( NSString * )path
{
    BOOL isDir = NO;
    BOOL doesNodeExist = [[ NSFileManager defaultManager ]
                    fileExistsAtPath: path isDirectory: &isDir ];
                    
    return( isDir && doesNodeExist );
}

- ( void )setUpNodeCell: ( NSString * )nodePath forCell: ( NSBrowserCell * )cell
{
    BOOL dir = [ self isDirectory: nodePath ];
    
    if ( dir == YES && !( [[ NSWorkspace sharedWorkspace ] isFilePackageAtPath: nodePath ] )) {
        [ cell setLeaf: NO ];
    } else {
        [ cell setLeaf: YES ];
    }
}

- ( NSDictionary * )statInformationForPath: ( NSString * )path
{
    struct stat		st;
    struct passwd	*pw;
    struct group	*gr;
    const char		*cpath = [ path UTF8String ];
    char		resolvedlink[ MAXPATHLEN ];
    BOOL		isAlias = NO;
    NSString		*resolvedpath = nil, *ext = [ path pathExtension ];
    NSString		*type = @"", *mode = @"";
    NSString		*owner = nil, *group = nil;
    NSString		*date = nil;
    NSDate		*theDate = nil;
    NSImage		*icon = nil;
    NSMutableDictionary	*dict = nil;
    
    if ( lstat( cpath, &st ) < 0 ) {
        NSLog( @"lstat %@: %s", path, strerror( errno ));
        return( nil );
    }
    
    switch ( st.st_mode & S_IFMT ) {
    case S_IFLNK:
        if ( realpath( cpath, resolvedlink ) < 0 ) {
            NSLog( @"readlink %@: %s", path, strerror( errno ));
            return( nil );
        }
        resolvedpath = [ NSString stringWithUTF8String: resolvedlink ];
        icon = [[ NSWorkspace sharedWorkspace ] iconForFile: path ];
        
        isAlias = YES;
        type = NSLocalizedString( @"symbolic link", @"symbolic link" );
        
        break;
        
    default:
    case S_IFREG:
        /* only check if a file's an alias if it has a size of 0 */
        if ( st.st_size == 0 ) {
            if ( [ path isAliasFile ] ) {
                if (( resolvedpath = [ path stringByResolvingAliasInPath ] ) != nil ) {
                    isAlias = YES;
                    type = NSLocalizedString( @"alias", @"alias" );
                }
            }
        }
        
        if ( ! isAlias ) {
            if (( icon = [ NSImage iconForFile: path ] ) == nil ) {
                if ( [ ext isEqualToString: @"" ] ) {
                    icon = [ NSImage iconForType: @"'doc '" ];
                } else {
                    icon = [ NSImage iconForType: ext ];
                }
            }
            type = NSLocalizedString( @"file", @"file" );
        }

        break;
        
    case S_IFDIR:
        if (( icon = [ NSImage iconForFile: path ] ) == nil ) {
            if ( [[ self bundleExtensions ] containsObject: ext ] ) {
                icon = [ NSImage iconForType: ext ];
            } else {
                icon = [ NSImage iconForType: @"'fldr'" ];
            }
        }
        type = NSLocalizedString( @"directory", @"directory" );
        break;
        
    case S_IFIFO:
        icon = [ NSImage iconForType: @"'doc '" ];
        type = NSLocalizedString( @"named pipe", @"named pipe" );
        break;
        
    case S_IFCHR:
        icon = [ NSImage iconForType: @"'doc '" ];
        type = NSLocalizedString( @"character special", @"character special" );
        break;
        
    case S_IFBLK:
        icon = [ NSImage iconForType: @"'doc '" ];
        type = NSLocalizedString( @"block special", @"block special" );
        break;
    
    case S_IFSOCK:
        icon = [ NSImage iconForType: @"'doc '" ];
        type = NSLocalizedString( @"socket", @"socket" );
        break;
    }
    
    dict = [[ NSMutableDictionary alloc ] init ];
    
    if ( icon == nil ) {
        if ( isAlias ) {
            icon = [[ NSWorkspace sharedWorkspace ] iconForFile: path ];
        }
        
        if ( icon == nil ) {
            icon = [ NSImage iconForType: @"'doc '" ];
        }
    }
    [ icon setScalesWhenResized: YES ];
    [ icon setSize: NSMakeSize( 16.0, 16.0 ) ];
    
    [ dict setObject: icon forKey: @"icon" ];
    if ( resolvedpath != nil ) {
        [ dict setObject: resolvedpath forKey: @"resolvedAlias" ];
    }
    
    if (( pw = getpwuid( st.st_uid )) == NULL ) {
        owner = [ NSString stringWithFormat: @"%d", st.st_uid ];
    } else {
        owner = [ NSString stringWithUTF8String: pw->pw_name ];
    }

    if (( gr = getgrgid( st.st_gid )) == NULL ) {
        group = [ NSString stringWithFormat: @"%d", st.st_gid ];
    } else {
        group = [ NSString stringWithUTF8String: gr->gr_name ];
    }
    
    [ dict setObject: owner forKey: @"owner" ];
    [ dict setObject: group forKey: @"group" ];
    
    mode = [ NSString stringWithFormat: @"%.4lo", ( unsigned long )0x0FFF & st.st_mode ];
    
    [ dict setObject: mode forKey: @"perm" ];
    [ dict setObject: type forKey: @"type" ];
    
    theDate = [ NSDate dateWithTimeIntervalSince1970: st.st_mtime ];
    if (( sixmo_in_secs() - st.st_mtime ) < now() &&
                ( sixmo_in_secs() + st.st_mtime ) > now()) {
        date = [ theDate descriptionWithCalendarFormat: @"%b %e %H:%M"
                            timeZone: [ NSTimeZone defaultTimeZone ] locale: nil ];
    } else {
        date = [ theDate descriptionWithCalendarFormat: @"%b %e %Y"
                        timeZone: [ NSTimeZone defaultTimeZone ]  locale: nil ];
    }
    [ dict setObject: [ NSString stringWithFormat: @"%lld", st.st_size ]
                            forKey: @"size" ];
    [ dict setObject: date forKey: @"date" ];
    [ dict setObject: path forKey: @"name" ];
    
    return( [ dict autorelease ] );
}

- ( NSMutableArray * )itemsAtPath: ( NSString * )path showHiddenFiles: ( BOOL )showHidden
{
    int			i;
    NSAutoreleasePool   *pool = [[ NSAutoreleasePool alloc ] init ];
    NSArray		*allItems = [[ NSFileManager defaultManager ] directoryContentsAtPath: path ];
    NSMutableArray 	*items = [[ NSMutableArray alloc ] init ];
    NSString		*tpath = [ path copy ], *fullpath = nil;
    NSDictionary	*item = nil;

    [ NSImage cacheIconsForPath: path contents: allItems ];
    
    /* add .. first */
    fullpath = [ tpath stringByAppendingPathComponent: @".." ];
    if (( item = [ self statInformationForPath: fullpath ] ) == nil ) {
	NSLog( @"couldn't retrive stat information for %@", fullpath );
    } else {
	[ items addObject: item ];
    }
    
    for ( i = 0; i < [ allItems count ]; i++ ) {
        if ( ! showHidden ) {
            if ( [ path isEqualToString: @"/" ] ) {
                if ( [[ self invisibles ] containsObject: [ allItems objectAtIndex: i ]] ) {
                    continue;
                }
            }
                
            if ( [[ allItems objectAtIndex: i ] characterAtIndex: 0 ] == '.' ) {
                continue;
            }
        }
    
        fullpath = [ tpath stringByAppendingPathComponent: [ allItems objectAtIndex: i ]];

        if (( item = [ self statInformationForPath: fullpath ] ) == nil ) {
            NSLog( @"couldn't retrieve information for %@", fullpath );
            continue;
        }
        [ items addObject: item ];
    }
    [ pool release ];
    [ tpath release ];
    
    return( [ items autorelease ] );
}

@end
