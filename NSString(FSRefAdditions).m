/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "NSString(FSRefAdditions).h"

@implementation NSString(FSRefAdditions)
#ifdef notdef
- ( Str255 * )pascalString
{
    OSErr			err;
    CFStringRef			cfstring;
    Str255			pstring;
    const char			*cstring;
    
    if ( self == nil || [ self isEqualToString: @"" ] ) {
	return( NULL );
    }
    
    cstring = [ self UTF8String ];
    
    if (( cfstring = CFStringCreateWithCString( NULL, cstring,
		CFStringGetSystemEncoding())) == NULL ) {
	NSLog( @"CFStringCreateFromCString failed." );
	return( NULL );
    }
    
    if (( *pstring = CFStringGetPascalString( cfstring, pstring,
		sizeof( cfstring ), CFStringGetSystemEncoding())) == NULL ) {
	NSLog( @"CFStringGetPascalString failed." );
	return( NULL );
    }
    
    return( &pstring );
}
#endif /* notdef */

+ ( NSString * )stringWithFSRef: ( FSRef * )fsref
{
    CFURLRef		cfurl;
    
    if (( cfurl = CFURLCreateFromFSRef( kCFAllocatorDefault, fsref )) == NULL ) {
	NSLog( @"CFURLCreateFromFSRef failed." );
	return( nil );
    }
    [ ( NSURL * )cfurl autorelease ];

    return( [ ( NSURL * )cfurl path ] );
}

+ ( NSString * )stringWithFSSpec: ( FSSpec * )fsspec
{
    OSErr		err;
    FSRef		ref;
    
    err = FSpMakeFSRef( fsspec, &ref );
	
    if ( err != noErr ) {
	NSLog( @"FSpMakeFSRef failed: error %d", err );
	return( nil );
    }
    
    return( [ self stringWithFSRef: &ref ] );
}

+ ( NSString * )stringWithAlias: ( AliasHandle )alias
{
    OSErr		err;
    FSRef		ref;
    Boolean		changed;
    unsigned long	flags = ( kResolveAliasTryFileIDFirst | kResolveAliasFileNoUI );
    
    if (( err = FSResolveAliasWithMountFlags( NULL, alias,
			&ref, &changed, flags )) != noErr ) {
	NSLog( @"FSResolveAlias failed: error %d", err );
	return( nil );
    }

    return( [ self stringWithFSRef: &ref ] );
}

- ( OSStatus )makeFSRefRepresentation: ( FSRef * )ref
{
    OSStatus		status;
    
    status = FSPathMakeRef(( UInt8 * )[ self fileSystemRepresentation ], ref, NULL );
    
    if ( status != noErr ) {
	NSLog( @"FSPathMakeRef failed: error %d", status );
    }
    
    return( status );
}

- ( OSStatus )makeFSSpec: ( FSSpec * )spec
{
    FSRef		ref;
    OSStatus		status;
    
    if (( status = [ self makeFSRefRepresentation: &ref ] ) != noErr ) {
        return( status );
    }
    
    if (( status = FSGetCatalogInfo( &ref, kFSCatInfoNone,
                        NULL, NULL, spec, NULL )) != noErr ) {
        return( status );
    }
    
    return( status );
}

- ( NSString * )stringByResolvingAliasInPath
{
    Boolean		isDir, isAlias;
    FSRef		ref;
    OSStatus		status;
    
    if ( [ self makeFSRefRepresentation: &ref ] != noErr ) {
	return( self );
    }
    
    if (( status = FSResolveAliasFileWithMountFlags( &ref, TRUE,
	    &isDir, &isAlias, kResolveAliasFileNoUI )) != noErr ) {
	NSLog( @"FSResolveAliasFile returned error %d", status );
	return( self );
    }
    
    if ( isAlias ) {
	return( [ NSString stringWithFSRef: &ref ] );
    }
    
    return( self );
}

- ( BOOL )isAliasFile
{
    FSRef		ref;
    Boolean		isDir, isAlias;
    OSErr		err;
    
    if ( [ self makeFSRefRepresentation: &ref ] != noErr ) {
        return( NO );
    }
    
    if (( err = FSIsAliasFile( &ref, &isAlias, &isDir )) != noErr ) {
        return( NO );
    }
    
    return(( BOOL )isAlias );
}

@end
