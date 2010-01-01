/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Foundation/Foundation.h>
#import "SFTPController.h"

@interface SFTPErrorHandler : NSObject {

}

- ( void )runErrorPanel: ( NSString * )theError;
- ( void )fatalErrorPanel: ( NSString * )fatalError;
@end
