/*
 * Copyright (c) 2008 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */
 
#import <Foundation/Foundation.h>

#include <Security/SecBase.h>
#include <Security/SecKeychain.h>
#include <Security/SecKeychainItem.h>

@interface UMKeychain : NSObject
{
    SecKeychainRef	_umKeychainRef;
}

+ ( UMKeychain * )defaultKeychain;

/* accessor methods */
- ( void )setKeychainRef: ( SecKeychainRef )keychainRef;
- ( SecKeychainRef )keychainRef;

- ( NSString * )passwordForService: ( NSString * )service
		account: ( NSString * )account
		keychainItem: ( SecKeychainItemRef * )item
		error: ( OSStatus * )error;
- ( OSStatus )storePassword: ( NSString * )password
		forService: ( NSString * )service
		account: ( NSString * )account
		keychainItem: ( SecKeychainItemRef * )item;
- ( OSStatus )changePassword: ( NSString * )newPassword
		forKeychainItem: ( SecKeychainItemRef )item;

@end
