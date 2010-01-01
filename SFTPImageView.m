/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SFTPImageView.h"

@implementation NSImageCell(DraggableExtensions)

- ( NSImage * )scaledImage
{
    return( _scaledImage );
}

@end



@implementation SFTPImageView

- ( void )awakeFromNib
{
    _imageLocationPath_ = nil;
}

/* allow user to drag image out of image view */
- ( void )mouseDown: ( NSEvent * )theEvent
{
    NSSize		dragOffset = NSMakeSize( 0.0, 0.0 );
    NSPasteboard	*pboard;
    NSImage		*dragImage = nil;
    NSImage		*scaledImage = [[ self cell ] scaledImage ];
    NSPoint		point;
    NSArray		*paths = nil;
    
    point = NSMakePoint((( [ self bounds ].size.width - [ scaledImage size ].width ) / 2.0 ),
                        (( [ self bounds ].size.height - [ scaledImage size ].height ) / 2.0 ));

    pboard = [ NSPasteboard pasteboardWithName: NSDragPboard ];
    [ pboard declareTypes: [ NSArray arrayWithObjects: NSTIFFPboardType,
                                        NSFilenamesPboardType, nil ]
                owner: self ];
                
    [ pboard setData: [[ self image ] TIFFRepresentation ]
            forType: NSTIFFPboardType ];
    
    if ( [ self imageLocationPath ] != nil ) {
        paths = [ NSArray arrayWithObject: [ self imageLocationPath ]];
        [ pboard setPropertyList: paths forType: NSFilenamesPboardType ];
    }
    
    dragImage = [[ NSImage alloc ] initWithSize: [ scaledImage size ]];
    [ dragImage lockFocus ];
    [ scaledImage dissolveToPoint: NSMakePoint( 0.0, 0.0 )
                    fraction: 0.5 ];
    [ dragImage unlockFocus ];
    
    [ self dragImage: dragImage at: point
            offset: dragOffset event: theEvent pasteboard: pboard
            source: self slideBack: YES ];
    [ dragImage release ];
}

- ( BOOL )needsPanelToBecomeKey
{
    return( YES );
}

- ( BOOL )acceptsFirstResponder
{
    return( YES );
}

- ( unsigned int )draggingSourceOperationMaskForLocal: ( BOOL )isLocal
{
    if ( isLocal ) {
        return( NSDragOperationNone );
    }
    
    return( NSDragOperationGeneric | NSDragOperationCopy );
}

- ( void )setImageLocationPath: ( NSString * )path
{
    if ( _imageLocationPath_ != nil ) {
        [ _imageLocationPath_ release ];
        _imageLocationPath_ = nil;
    }
    
    if ( path == nil || [ path isEqualToString: @"" ] ) {
        return;
    }
    
    _imageLocationPath_ = [[ NSString alloc ] initWithString: path ];
}

- ( NSString * )imageLocationPath
{
    return( _imageLocationPath_ );
}

@end