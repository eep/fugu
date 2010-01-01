/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <AppKit/AppKit.h>

@interface NSPanel(Resizing)

- ( void )resizeForContentView: ( NSView * )view display: ( BOOL )display
	animate: ( BOOL )animate;
- ( void )resizeForContentView: ( NSView * )view animate: ( BOOL )animate;
- ( void )resizeForContentView: ( NSView * )view;

@end
