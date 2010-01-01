/*
 * Copyright (c) 2005 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Cocoa/Cocoa.h>

@interface UMDragDropImageView : NSImageView
{
    id		_umDragDropImageViewDelegate;
}

- ( void )setDelegate: ( id )delegate;
- ( id )delegate;

@end

/* delegate methods */
@interface NSObject(UMDragDropImageView)
- ( void )dropImageViewChanged: ( NSDictionary * )changeDictionary;
@end