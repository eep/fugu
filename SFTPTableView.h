/*
 * Copyright (c) 2005 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Cocoa/Cocoa.h>

/* column minimum widths */
#define DATE_COLUMN_WIDTH	100.0
#define GROUP_COLUMN_WIDTH	70.0
#define MODE_COLUMN_WIDTH	80.0
#define OWNER_COLUMN_WIDTH	70.0
#define SIZE_COLUMN_WIDTH	70.0

@interface SFTPTableView : NSTableView
{
@private
    int		    rightClickedRow;
    int		    _sftpDragPhase;
    NSTimer	    *springLoadedTimer;
    NSImage	    *_sftpOriginalDragImage;
    NSArray	    *_sftpOriginalPboardTypes;
    NSMutableArray  *_sftpOriginalPboardPlists;
    BOOL	    _sftpDragPromisedFiles;

    NSTimer	    *_sftpTableViewClickTimer;
    int		    _sftpLastSelectedRow;
}

- ( void )keyDown: ( NSEvent * )theEvent;
- ( int )rightClickedRow;

- ( NSPoint )originOfSelectedCell;

- ( void )addTableColumnWithIdentifier: ( id )identifier
            columnTitle: ( NSString * )title width: ( float )width;
	    
- ( BOOL )dragPromisedFiles;
- ( void )setDragPromisedFiles: ( BOOL )promised;

/* renaming helper methods */
- ( void )restartClickTimer;
- ( void )clearClickTimer;
- ( int )lastSelectedRow;
- ( void )setLastSelectedRow: ( int )row;

@end

/* to assist column creation in delegate */
NSString 	*ColumnTitleFromIdentifier( NSString *identifier );
float		WidthForColumnWithIdentifier( NSString *identifier );


/* additional delegate methods */
@interface NSObject(SFTPTableViewEventDelegate)

- ( BOOL )handleEvent: ( NSEvent * )theEvent fromTable: ( SFTPTableView * )table;
- ( BOOL )handleChangedText: ( NSString * )newstring forTable: ( SFTPTableView * )table
            column: ( int )column;
- ( NSMenu * )menuForTable: ( SFTPTableView * )table
            column: ( int )column
            row: ( int )row;

@end

/* additional dataSource methods */
@interface NSObject(SFTPTableViewDataSource)
- ( NSArray * )promisedNamesFromPlists: ( id )plist;
- ( BOOL )handleDroppedPromisedFiles: ( NSArray * )promisedFiles
	    destination: ( NSString * )dropDestination;
@end