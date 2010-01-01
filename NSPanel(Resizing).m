/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "NSPanel(Resizing).h"

@implementation NSPanel(Resizing)

- ( float )toolbarHeight
{
    float		height = 0.0;
    NSToolbar		*toolbar;
    NSRect		rect;
    
    toolbar = [ self toolbar ];
    
    if ( toolbar != nil && [ toolbar isVisible ] ) {
	rect = [ NSWindow contentRectForFrameRect: [ self frame ]
			    styleMask: [ self styleMask ]];
	height = NSHeight( rect ) - NSHeight( [[ self contentView ] frame ] );
    }
    
    return( height );
}

- ( void )resizeForContentView: ( NSView * )view display: ( BOOL )display
	    animate: ( BOOL )animate
{
    NSRect		newRect, windowRect, contentRect;
    
    if ( view == nil ) {
	return;
    }
    
    newRect = [ view frame ];
    windowRect = [ self frame ];
    contentRect = [[ self contentView ] frame ];
     
    windowRect.origin.y += ( NSHeight( contentRect ) - NSHeight( newRect ));
    windowRect.size.height -= ( NSHeight( contentRect ) - NSHeight( newRect ));
    
    [ self setFrame: windowRect display: display animate: animate ];
}

- ( void )resizeForContentView: ( NSView * )view animate: ( BOOL )animate
{
    [ self resizeForContentView: view display: YES animate: animate ];
}

- ( void )resizeForContentView: ( NSView * )view
{
    [ self resizeForContentView: view animate: YES ];
}

@end
