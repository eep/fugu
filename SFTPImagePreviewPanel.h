/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <AppKit/AppKit.h>


@interface SFTPImagePreviewPanel : NSPanel {

}

- ( void )zoomFromRect: ( NSRect )originRect toRect: ( NSRect )destRect;

@end
