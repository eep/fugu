/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SFTPImagePreviewPanel.h"


@implementation SFTPImagePreviewPanel

- ( NSTimeInterval )animationResizeTime: ( NSRect )rect
{
    return(( NSTimeInterval )0.25 );
}

- ( void )zoomFromRect: ( NSRect )originRect toRect: ( NSRect )destRect
{
    [ self setFrame: originRect display: NO animate: NO ];
    [ self makeKeyAndOrderFront: nil ];
    [ self setFrame: destRect display: YES animate: YES ];
}

@end
