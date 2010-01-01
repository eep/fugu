/*
 * Copyright (c) 2005 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "UMTextField.h"

@implementation UMTextField

- ( void )setDelegate: ( id )delegate
{
    _umTextFieldDelegate = delegate;
}

- ( id )delegate
{
    return( _umTextFieldDelegate );
}

- ( id )initWithFrame: ( NSRect )frame {
    self = [ super initWithFrame: frame ];
    _umTextFieldDelegate = nil;
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
    
    if ( ! [[ pb types ] containsObject: NSFilenamesPboardType ] &&
	    ! [[ pb types ] containsObject: NSURLPboardType ] ) {
	return( NSDragOperationNone );
    }
	
    [ self setBackgroundColor: [ NSColor lightGrayColor ]];
    [ self setEditable: NO ];
    [ self setNeedsDisplay: YES ];
    
    return( NSDragOperationCopy );
}

- ( void )draggingExited: ( id <NSDraggingInfo> )sender
{
    [ self setBackgroundColor: [ NSColor controlBackgroundColor ]];
    [ self setEditable: YES ];
    [ self setNeedsDisplay: YES ];
}

- ( BOOL )performDragOperation: ( id <NSDraggingInfo> )sender
{
    NSPasteboard	*pb = [ sender draggingPasteboard ];
    NSString		*path = nil;
    
    if ( [[ pb types ] containsObject: NSFilenamesPboardType ] ) {
	NSArray		*files;
	
	files = [ pb propertyListForType: NSFilenamesPboardType ];
	
	/* first item wins */
	path = [ files objectAtIndex: 0 ];
    } else if ( [[ pb types ] containsObject: NSURLPboardType ] ) {
	path = [ pb stringForType: NSURLPboardType ];
    }
    
    if ( path == nil ) {
	return( NO );
    }
    
    [ self setStringValue: path ];
    [ self setEditable: YES ];
    [ self setBackgroundColor: [ NSColor controlBackgroundColor ]];
    [ self setNeedsDisplay: YES ];
    
    if ( [[ self delegate ] respondsToSelector:
	    @selector( umTextFieldContentsChanged: ) ] ) {
	[[ self delegate ] umTextFieldContentsChanged:
		[ NSDictionary dictionaryWithObjectsAndKeys:
		self, @"UMTextField",
		path, @"UMTextFieldString", nil ]];
    }
    
    return( YES );
}

@end
