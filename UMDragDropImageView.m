/*
 * Copyright (c) 2005 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "UMDragDropImageView.h"

/*
 * NSImageView subclass capable of accepting drops.
 * The image of the view is set to the icon of the
 * dropped file.
 */

@implementation UMDragDropImageView

- ( void )setDelegate: ( id )delegate
{
    _umDragDropImageViewDelegate = delegate;
}

- ( id )delegate
{
    return( _umDragDropImageViewDelegate );
}

- ( id )initWithFrame: ( NSRect )frame {
    self = [ super initWithFrame: frame ];
    _umDragDropImageViewDelegate = nil;
    return( self );
}

- ( void )drawRect: ( NSRect )rect {
    [ super drawRect: rect ];
}

- ( void )awakeFromNib
{
    [ self registerForDraggedTypes: [ NSArray arrayWithObjects:
	    NSFilenamesPboardType, NSURLPboardType, nil ]];
}

- ( NSDragOperation )draggingEntered: ( id <NSDraggingInfo> )sender
{
    NSPasteboard	*pb = [ sender draggingPasteboard ];
    NSString		*type = nil;
    
    type = [ pb availableTypeFromArray: [ NSArray arrayWithObjects:
		    NSFilenamesPboardType, NSURLPboardType, nil ]];
    if ( type == nil ) {
	return( NSDragOperationNone );
    }
    
    return( NSDragOperationCopy );
}

- ( void )draggingExited: ( id <NSDraggingInfo> )sender
{
}

- ( BOOL )performDragOperation: ( id <NSDraggingInfo> )sender
{
    NSPasteboard	*pb = [ sender draggingPasteboard ];
    NSArray		*plist = nil;
    NSImage		*icon = nil;
    NSString		*type = nil;
    id			path = nil;
    
    type = [ pb availableTypeFromArray: [ NSArray arrayWithObjects:
		    NSFilenamesPboardType, NSURLPboardType, nil ]];
    if ( type == nil ) {
	return( NO );
    }
    
    path = [ pb stringForType: type ];
    plist = [ path propertyList ];
    path = [ plist objectAtIndex: 0 ];
    
    if ( [[ self delegate ] respondsToSelector:
	    @selector( dropImageViewChanged: ) ] ) {
	[[ self delegate ] dropImageViewChanged:
		[ NSDictionary dictionaryWithObjectsAndKeys:
		self, @"UMDragDropImageView",
		path, @"UMDragDropPath", nil ]];
    }
    
    icon = [[ NSWorkspace sharedWorkspace ] iconForFile: path ];
    
    [ self setImage: icon ];
    
    return( YES );
}

@end
