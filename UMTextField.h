/*
 * Copyright (c) 2005 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Cocoa/Cocoa.h>

@interface UMTextField : NSTextField
{
    id	    _umTextFieldDelegate;
}

- ( void )setDelegate: ( id )delegate;
- ( id )delegate;

@end

/* delegate methods */
@interface NSObject(UMTextField)
- ( void )umTextFieldContentsChanged: ( NSDictionary * )changeDictionary;
@end