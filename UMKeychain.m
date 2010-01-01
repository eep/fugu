/*
 * Copyright (c) 2008 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */
 
#import "UMKeychain.h"

#include <errno.h>
#include <pwd.h>
#include <stdlib.h>
#include <string.h>

@implementation UMKeychain

static UMKeychain	*defaultKeychain = nil;

- ( id )init
{
    self = [ super init ];
    _umKeychainRef = nil;
    
    return( self );
}

+ ( UMKeychain * )defaultKeychain
{
    OSStatus		err;
    SecKeychainRef	skcref;
    
    if ( defaultKeychain == nil ) {
	defaultKeychain = [[ UMKeychain alloc ] init ];
	
	if (( err = SecKeychainCopyDefault( &skcref )) != noErr ) {
	    NSLog( @"SecKeychainCopyDefault failed: error %d", err );
	    return( nil );
	}
	[ defaultKeychain setKeychainRef: skcref ];
    }
    
    return( defaultKeychain );
}

- ( void )setKeychainRef: ( SecKeychainRef )keychainRef
{
    if ( _umKeychainRef != NULL ) {
	CFRelease( _umKeychainRef );
    }
    _umKeychainRef = keychainRef;
}

- ( SecKeychainRef )keychainRef
{
    return( _umKeychainRef );
}

- ( NSString * )passwordForService: ( NSString * )service
		account: ( NSString * )account
		keychainItem: ( SecKeychainItemRef * )item
		error: ( OSStatus * )error
{
    NSString		*foundPassword = nil;
    OSStatus		err;
    UInt32		len;
    char		*password;
    
    if (( password = ( char * )malloc( _PASSWORD_LEN + 1 )) == NULL ) {
	NSLog( @"malloc: %s", strerror( errno ));
	return( nil );
    }
    
FindKeychainPassword:
    err = SecKeychainFindGenericPassword( [ self keychainRef ],
		[ service length ], [ service UTF8String ],
		[ account length ], [ account UTF8String ],
		&len, ( void ** )&password, item );
    
    switch ( err ) {
    case 0:
	password[ len ] = '\0';
	foundPassword = [ NSString stringWithUTF8String: password ];
	break;
	
    case errSecBufferTooSmall:
	NSLog( @"password buffer too small, realloc'ing" );
	if (( password = ( char * )realloc( password, 4096 )) == NULL ) {
	    NSLog( @"realloc: %s", strerror( errno ));
	    /* everything's wrong. die. */
	    exit( 2 );
	}
	goto FindKeychainPassword;
	
    default:
	/* calling object handles error */
	break;
    }
    
    free( password );
    
    return( foundPassword );
}

- ( OSStatus )storePassword: ( NSString * )password
		forService: ( NSString * )service
		account: ( NSString * )account
		keychainItem: ( SecKeychainItemRef * )item
{
    OSStatus		err;
    
    err = SecKeychainAddGenericPassword( [ self keychainRef ],
		[ service length ], [ service UTF8String ],
		[ account length ], [ account UTF8String ],
		[ password length ], ( const void * )[ password UTF8String ],
		item );
		
    return( err );
}

- ( OSStatus )changePassword: ( NSString * )newPassword
		forKeychainItem: ( SecKeychainItemRef )item
{
    OSStatus		err;
    
    err = SecKeychainItemModifyAttributesAndData( item, NULL,
	    [ newPassword length ], ( const void * )[ newPassword UTF8String ]);
	    
    return( err );
}

@end
