/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Cocoa/Cocoa.h>

@interface SFTPImageView : NSImageView
{
@private
    NSString		*_imageLocationPath_;
}

- ( void )mouseDown: ( NSEvent * )theEvent;
- ( BOOL )needsPanelToBecomeKey;
- ( BOOL )acceptsFirstResponder;

- ( void )setImageLocationPath: ( NSString * )path;
- ( NSString * )imageLocationPath;

@end