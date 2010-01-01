/*
 * Copyright (c) 2005 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SFTPTableView.h"

@implementation SFTPTableView

- ( id )init
{
    self = [ super init ];
    _sftpOriginalDragImage = nil;
    _sftpOriginalPboardTypes = nil;
    _sftpOriginalPboardPlists = nil;
    _sftpDragPhase = 0;
    _sftpDragPromisedFiles = NO;
    
    _sftpLastSelectedRow = -1;
    _sftpTableViewClickTimer = nil;
    
    return( self );
}

- ( void )restartClickTimer
{
    _sftpTableViewClickTimer = [ NSTimer scheduledTimerWithTimeInterval: 1.0
					    target: self
					    selector: @selector( timerBeginEditingName: )
					    userInfo: nil
					    repeats: NO ];
}

- ( void )clearClickTimer
{
    if ( _sftpTableViewClickTimer != nil ) {
	[ _sftpTableViewClickTimer invalidate ];
    }
    _sftpTableViewClickTimer = nil;
    
    [ self setLastSelectedRow: -1 ];
}

- ( int )lastSelectedRow
{
    return( _sftpLastSelectedRow );
}

- ( void )setLastSelectedRow: ( int )row
{
    _sftpLastSelectedRow = row;
}

- ( BOOL )dragPromisedFiles
{
    return( _sftpDragPromisedFiles );
}

- ( void )setDragPromisedFiles: ( BOOL )promised
{
    _sftpDragPromisedFiles = promised;
}

- ( void )timerBeginEditingName: ( NSTimer * )timer
{
    int		row = [ self selectedRow ];
    id		cell;

    if ( row < 0 ) {
	return;
    }

    cell = [[[ self tableColumns ] objectAtIndex: 0 ]
		dataCellForRow: row ];

    [ cell setEditable: YES ];
    [ cell setScrollable: YES ];
    [ self selectRow: row byExtendingSelection: NO ];

    [ self editColumn: 0 row: row
	    withEvent: nil
	    select: YES ];

    _sftpTableViewClickTimer = nil;
}

/* catch key events */
- ( void )keyDown: ( NSEvent * )theEvent
{
    if ( ! [[ self delegate ] handleEvent: theEvent fromTable: self ] ) {
        [ super keyDown: theEvent ];
    }
}

- ( void )dragImage: ( NSImage * )anImage at: ( NSPoint )imageLoc offset: ( NSSize )mouseOffset
        event: ( NSEvent * )theEvent pasteboard: ( NSPasteboard * )pboard
	source: ( id )sourceObject slideBack: ( BOOL )slideBack
{
    int                 row = [ self rowAtPoint: imageLoc ];
    NSRect		imageframe = [ self frameOfCellAtColumn: 0 row: row ];
    NSRect		imageRect;
    float		width = NSWidth( imageframe );
    float		height = NSHeight( imageframe );
    NSSize		imagesize;
    NSImage		*image = nil;
    NSView		*view = nil;
    int			i;

    if ( _sftpDragPhase == 0 ) {
	/*
	 * phase 0: capture image and original pasteboard
	 * contents, then drag promised files if required
	 */
	if (( view = [[ self superview ] superview ] ) == nil ) {
	    view = self;
	}
	height = NSHeight( [ view frame ] );

	imagesize = NSMakeSize( width, height );
	image = [[ NSImage alloc ] initWithSize: imagesize ];
    
	/* only draw the portion from the filename column */
	[ image lockFocus ];
	[ anImage dissolveToPoint: NSZeroPoint fraction: 1.0 ];
	[ image unlockFocus ];
	
	if ( ! [ self dragPromisedFiles ] ) {
	    [ super dragImage: image at: imageLoc offset: mouseOffset
		event: theEvent pasteboard: pboard source: sourceObject
		slideBack: slideBack ];
	    [ image release ];
	    return;
	}
	
	_sftpOriginalDragImage = [ image retain ];
	_sftpOriginalPboardTypes = [[ pboard types ] copy ];
	
	if ( _sftpOriginalPboardPlists ) {
	    [ _sftpOriginalPboardPlists release ];
	    _sftpOriginalPboardPlists = nil;
	}
	_sftpOriginalPboardPlists = [[ NSMutableArray alloc ] init ];
	for ( i = 0; i < [ _sftpOriginalPboardTypes count ]; i++ ) {
	    [ _sftpOriginalPboardPlists addObject:
		    [ pboard propertyListForType:
			[ _sftpOriginalPboardTypes objectAtIndex: i ]]];
	}
	_sftpDragPhase = 1;
	
	imageRect.origin = imageLoc;
	imageRect.size = NSMakeSize( 0.0, 0.0 );
	
	[ self dragPromisedFilesOfTypes: [ NSArray arrayWithObject: @"'doc '" ]
		    fromRect: imageRect source: self slideBack: YES event: theEvent ];
		    
	[ image release ];
    } else {
	/*
	 * phase 1: restore original image; add old pasteboard
	 * contents; and let super do all the rest
	 */
	NSArray		*types = _sftpOriginalPboardTypes;
	id		plist;
	int		i;

	[ pboard addTypes: types owner: [ self delegate ]];
	for ( i = 0; i < [ types count ]; i++ ) {
	    plist = [ _sftpOriginalPboardPlists objectAtIndex: i ];
	    [ pboard setPropertyList: plist forType: [ types objectAtIndex: i ]];
	}
	[ _sftpOriginalPboardPlists retain ];
	
	[ super dragImage: _sftpOriginalDragImage at: imageLoc offset: mouseOffset
		event: theEvent pasteboard: pboard source: sourceObject
		slideBack: slideBack ];
		
	if ( _sftpOriginalDragImage ) {
	    [ _sftpOriginalDragImage release ];
	    _sftpOriginalDragImage = nil;
	}
	if ( _sftpOriginalPboardTypes ) {
	    [ _sftpOriginalPboardTypes release ];
	    _sftpOriginalPboardTypes = nil;
	}
	if ( _sftpOriginalPboardPlists ) {
	    [ _sftpOriginalPboardPlists release ];
	    /*
	     * second release in next phase 0 or
	     * namesOfPromisedFilesDroppedAtDestination
	     */
	}
	_sftpDragPhase = 0;
    }
}

- ( NSArray * )namesOfPromisedFilesDroppedAtDestination: ( NSURL * )url
{
    NSArray	    *plists = _sftpOriginalPboardPlists;
    NSArray	    *names = [[ self dataSource ] promisedNamesFromPlists: plists ];
    BOOL	    handled;
					    
    handled = [[ self dataSource ]
		    handleDroppedPromisedFiles: [ plists objectAtIndex: 0 ]
		    destination: [ url path ]];
    if ( ! handled ) {
	NSLog( @"failed to handle promised files" );
    }
    
    [ _sftpOriginalPboardPlists release ];
    _sftpOriginalPboardPlists = nil;
    
    return( names );
}

- ( NSDragOperation )draggingSourceOperationMaskForLocal: ( BOOL )isLocal
{
    return( NSDragOperationCopy );
}

- ( void )draggedImage: ( NSImage * )image endedAt: ( NSPoint )point
	    operation: ( NSDragOperation )operation
{
    /* work around a bug in Panther */
    [[ NSPasteboard pasteboardWithName: NSDragPboard ]
	    declareTypes: nil owner: nil ];
}

- ( void )doSpringLoadedAction: ( NSTimer * )timer
{
    [[ self delegate ] performSelector:
                    @selector( performSpringLoadedActionInTable: )
                                    withObject: self
                                    afterDelay: 0.0 ];
                                    
    [ springLoadedTimer invalidate ];
    springLoadedTimer = nil;
}

#ifdef SPRINGLOADED
- ( NSDragOperation )draggingEntered: ( id <NSDraggingInfo> )sender
{
    [ springLoadedTimer invalidate ];
    springLoadedTimer = nil;
    
    if ( [[ self delegate ] respondsToSelector:
                    @selector( performSpringLoadedActionInTable: ) ] ) {
        springLoadedTimer = [ NSTimer scheduledTimerWithTimeInterval: 2.0
                                        target: self
                                        selector: @selector( doSpringLoadedAction: )
                                        userInfo: nil
                                        repeats: NO ];
    }
    
    return( [ super draggingEntered: sender ] );
}
#endif /* SPRINGLOADED */

/* watch for keydown events while dragging for spring-loaded folders */
- ( NSDragOperation )draggingUpdated: ( id <NSDraggingInfo> )sender
{
    NSEvent         *e = [ NSApp currentEvent ];
    NSEventType     type = [ e type ];
    NSDragOperation op = [ super draggingUpdated: sender ];
    
    if ( type == NSKeyDown ) {
        NSEvent         *newEvent = nil;
        NSPoint         pt;
        unichar         key = [[ e charactersIgnoringModifiers ] characterAtIndex: 0 ];
        
        if ( key == ' ' ) {
            if ( [[ self delegate ] respondsToSelector:
                            @selector( performSpringLoadedActionInTable: ) ] ) {
                [ springLoadedTimer invalidate ];
                springLoadedTimer = nil;
                
                [[ self delegate ] performSelector:
                    @selector( performSpringLoadedActionInTable: )
                                    withObject: self
                                    afterDelay: 0.0 ];
            }
        }
        
        pt = NSMakePoint( [ e locationInWindow ].x + 1, [ e locationInWindow ].y + 1 );
        
        /* send a fake event to avoid repeats */
        newEvent = [ NSEvent mouseEventWithType: NSLeftMouseDragged
                    location: pt modifierFlags: [ e modifierFlags ]
                    timestamp: ( [ e timestamp ] + 0.1 ) windowNumber: [ e windowNumber ]
                    context: [ e context ] eventNumber: 1
                    clickCount: 0 pressure: 0.0 ];
                    
        [ NSApp postEvent: newEvent atStart: YES ];
    }

    return( op );
}

- ( void )draggingExited: ( id <NSDraggingInfo> )sender
{
    if ( springLoadedTimer != nil ) {
        [ springLoadedTimer invalidate ];
        springLoadedTimer = nil;
    }
    
    if ( [[ self delegate ] respondsToSelector:
            @selector( springLoadedActionCancelledInTable: ) ] ) {
        [[ self delegate ] performSelector:
                    @selector( springLoadedActionCancelledInTable: )
                            withObject: self
                            afterDelay: 0.0 ];
    }
    
    [ super draggingExited: sender ];
}

#ifdef SPRINGLOADED
- ( void )mouseMoved: ( NSEvent * )event
{
    switch ( [ event type ] ) {
    case NSLeftMouseDragged:
        if ( springLoadedTimer != nil ) {
            [ springLoadedTimer invalidate ];
            springLoadedTimer = nil;
            springLoadedTimer = [ NSTimer scheduledTimerWithTimeInterval: 2.0
                                        target: self
                                        selector: @selector( doSpringLoadedAction: )
                                        userInfo: nil
                                        repeats: NO ];
        }
        
    default:
        break;
    }
    
    [ super mouseMoved: event ];
}
#endif /* SPRINGLOADED */

- ( BOOL )needsPanelToBecomeKey
{
    return( YES );
}

/* display contextual menus for both of the browsers */
- ( NSMenu * )menuForEvent: ( NSEvent * )event
{
    NSPoint	p = [ self convertPoint: [ event locationInWindow ]
                            fromView: nil ];
    int		column = [ self columnAtPoint: p ];
    int		row = [ self rowAtPoint: p ];
    
    rightClickedRow = 0;
    
    if ( column == 0 && row >= 0  &&
        [[ self delegate ] respondsToSelector:
                @selector( menuForTable:column:row: ) ] ) {
        rightClickedRow = row;
        [ self selectRow: row byExtendingSelection: NO ];
        
        return( [[ self delegate ] menuForTable: self
                                    column: column
                                    row: row ] );
    }
    return( nil );
}

- ( void )textDidEndEditing: ( NSNotification * )aNotification
{
    if ( [[[ aNotification userInfo ] objectForKey: @"NSTextMovement" ]
                                        intValue ] == NSReturnTextMovement ) {
        int		column = [ self editedColumn ];
        
        if ( ! [[ self delegate ] respondsToSelector:
                    @selector( handleChangedText:forTable:column: ) ] ) {
            NSBeep();
            [ super textDidEndEditing: aNotification ];
            return;
        }
        
        [[ self delegate ] handleChangedText: [[ aNotification object ] string ]
                forTable: self
                column: column ];
        [[ self window ] endEditingFor: self ];
        [[ self window ] makeFirstResponder: self ];
        [ self reloadData ];
    } else {
        [ super textDidEndEditing: aNotification ];
    }
}

- ( int )rightClickedRow
{
    return( rightClickedRow );
}

- ( NSPoint )originOfSelectedCell
{
    NSRect		cellframe;
    NSPoint		cellorigin;
    int			row = [ self selectedRow ];
    
    if ( row < 0 ) {
        return( NSZeroPoint );
    }
    
    cellframe = [ self frameOfCellAtColumn: 0 row: row ];
    cellorigin = NSMakePoint( cellframe.origin.x, cellframe.origin.y );
    
    cellorigin = [[[ self window ] contentView ] convertPoint: cellorigin fromView: self ];
    cellorigin = [[ self window ] convertBaseToScreen: cellorigin ];
    
    return( cellorigin );
}

- ( void )addTableColumnWithIdentifier: ( id )identifier
            columnTitle: ( NSString * )title width: ( float )width
{
    NSTableColumn	*column = nil;
    
    if ( identifier == nil || title == nil || [ title isEqualToString: @"" ] ) {
        return;
    }
    
    column = [[[ NSTableColumn alloc ] initWithIdentifier: identifier ]
                                        autorelease ];
                                        
    [[ column headerCell ] setStringValue: title ];
    [ column setMinWidth: ( width / 2 ) ];
    [ column setMaxWidth: ( width * 5 ) ];
    [ column setWidth: width ];
    if ( [ identifier isEqualToString: @"sizecolumn" ] ) {
        [[ column headerCell ] setAlignment: NSRightTextAlignment ];
        [[ column dataCell ] setAlignment: NSRightTextAlignment ];
    }
    
    [ self addTableColumn: column ];
}

    NSString *
ColumnTitleFromIdentifier( NSString *identifier )
{
    NSString		*title = @"";
    
    if ( [ identifier isEqualToString: @"datecolumn" ] ) {
        title = NSLocalizedString( @"Date", @"Date" );
    } else if ( [ identifier isEqualToString: @"groupcolumn" ] ) {
        title = NSLocalizedString( @"Group", @"Group" );
    } else if ( [ identifier isEqualToString: @"ownercolumn" ] ) {
        title = NSLocalizedString( @"Owner", @"Owner" );
    } else if ( [ identifier isEqualToString: @"permcolumn" ] ) {
        title = NSLocalizedString( @"Permissions", @"Permissions" );
    } else if ( [ identifier isEqualToString: @"sizecolumn" ] ) {
        title = NSLocalizedString( @"Size", @"Size" );
    }

    return( title );
}

    float
WidthForColumnWithIdentifier( NSString *identifier )
{
    float		width = 50.0; /* arbitrary non-zero width */
    
    if ( [ identifier isEqualToString: @"datecolumn" ] ) {
        width = DATE_COLUMN_WIDTH;
    } else if ( [ identifier isEqualToString: @"groupcolumn" ] ) {
        width = GROUP_COLUMN_WIDTH;
    } else if ( [ identifier isEqualToString: @"ownercolumn" ] ) {
        width = OWNER_COLUMN_WIDTH;
    } else if ( [ identifier isEqualToString: @"permcolumn" ] ) {
        width = MODE_COLUMN_WIDTH;
    } else if ( [ identifier isEqualToString: @"sizecolumn" ] ) {
        width = SIZE_COLUMN_WIDTH;
    }
    
    return( width );
}

@end
