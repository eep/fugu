/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Cocoa/Cocoa.h>

/*
 * Override animationResizeTime of superclass (NSWindow)
 */

@interface SFTPMainWindow : NSWindow {

}

- ( int )setTitleToLocalHostName;

@end
