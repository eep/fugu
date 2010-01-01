/*
 *
 * subclass of NSTextFieldCell that shows image and text. Based on
 * Apple's sample code for ImageAndTextCell in DragAndDropOutlineView.
 * 
 */

#import "SFTPItemCell.h"

@implementation SFTPItemCell

- ( id )init
{
    self = [ super init ];
    if ( self ) {
	image = nil;
    }
    
    return( self );
}

- ( void )dealloc
{
    [ image release ];
    image = nil;
    [ super dealloc ];
}

- copyWithZone: ( NSZone * )zone
{
    SFTPItemCell 	*cell = ( SFTPItemCell * )[ super copyWithZone: zone ];
    
    if ( [ self image ] ) {
	cell->image = [ image retain ];
    }
    [ cell setAttributedStringValue: [ self attributedStringValue ]];
    
    return( cell );
}

- ( void )italicizeStringValue
{
    NSMutableAttributedString	*as;
    NSFontManager		*fm;
    NSFont			*font;
    NSRange			range;
    unsigned int		i;
    
    range = [[ self stringValue ] rangeOfString: [ self stringValue ]];

    if (( i = range.location ) == NSNotFound ) { NSLog( @"not found" ); return; }
    
    fm = [ NSFontManager sharedFontManager ];
    as = [[ NSMutableAttributedString alloc ] init ];
    [ as setAttributedString: [ self attributedStringValue ]];
    while ( NSLocationInRange( i, range )) {
        font = [ fm convertFont: [ NSFont fontWithName: @"Helvetica" size: 11.0 ]
                    toHaveTrait: NSItalicFontMask ];
        [ as addAttribute: NSFontAttributeName value: font range: range ];
        i = NSMaxRange( range );
    }
    [ self setAttributedStringValue: as ];
    [ as release ];
}

- ( void )setImage: ( NSImage * )anImage
{
    if ( anImage != image ) {
        [ image release ];
        image = [ anImage retain ];
    }
}

- ( NSImage * )image
{
    return( image );
}

- ( NSRect )imageFrameForCellFrame: ( NSRect )cellFrame
{
    if ( image != nil ) {
        NSRect 		imageFrame;
        
        imageFrame.size = [ image size ];
        imageFrame.origin = cellFrame.origin;
        imageFrame.origin.x += 5;
        imageFrame.origin.y += ceil(( cellFrame.size.height - imageFrame.size.height ) / 2 );
        return( imageFrame );
    } else {
        return( NSZeroRect );
    }
}

- ( void )editWithFrame: ( NSRect )aRect inView: ( NSView * )controlView editor:( NSText * )textObj
            delegate: ( id )anObject event: ( NSEvent * )theEvent
{
    NSRect 		textFrame, imageFrame;
    
    NSDivideRect( aRect, &imageFrame, &textFrame, ( [ image size ].width + 5 ), NSMinXEdge );
    
    [ super editWithFrame: textFrame inView: controlView editor: textObj
            delegate: anObject event: theEvent ];
}

- ( void )selectWithFrame: ( NSRect )aRect inView: ( NSView * )controlView editor: ( NSText * )textObj
            delegate: ( id )anObject start: ( int )selStart length: ( int )selLength
{
    NSRect 		textFrame, imageFrame;
    
    NSDivideRect( aRect, &imageFrame, &textFrame, ( [ image size ].width + 5 ), NSMinXEdge );
    
    [ super selectWithFrame: textFrame inView: controlView editor: textObj
            delegate: anObject start: selStart length: selLength ];
}

/* center the string a little better when the font size isn't 12.0 */
- ( void )drawInteriorWithFrame: ( NSRect )cellFrame inView: ( NSView * )controlView
{
    static NSMutableDictionary	    *attributes = nil;
    static NSMutableParagraphStyle  *style = nil;
    NSColor			    *color = nil;
    NSRect			    drawFrame;
    double			    ht;
    
    if ( [ self stringValue ] == nil || [[ self stringValue ] isEqualToString: @"" ] ) {
	[ super drawInteriorWithFrame: cellFrame inView: controlView ];
	return;
    }

    drawFrame.size.height = NSHeight( cellFrame );
    drawFrame.size.width = NSWidth( cellFrame );
    drawFrame.origin.x = ( cellFrame.origin.x + 2 );
    drawFrame.origin.y = NSMidY( cellFrame );
    
    ht = ceil( [[ self attributedStringValue ] size ].height / 2 );
    if ( [ controlView isFlipped ] ) {
	drawFrame.origin.y -= ( ht - 1 );
    } else {
	cellFrame.origin.y += ( ht + 1 );
    }

    if ( style == nil ) {
	style = [[ NSParagraphStyle defaultParagraphStyle ] mutableCopy ];
	[ style setLineBreakMode: NSLineBreakByTruncatingMiddle ];
    }
    
    color = [ NSColor blackColor ];
    
    if ( attributes == nil ) {
	attributes = [[ NSMutableDictionary dictionaryWithObjectsAndKeys:
			[ self font ], NSFontAttributeName,
			style, NSParagraphStyleAttributeName,
			color, NSForegroundColorAttributeName, nil ] retain ];
    }
    
    /* draw the text in white if we're highlighted and 1st responder */
    if ( [ self isHighlighted ] && [ NSApp isActive ] &&
	    [[[[ self controlView ] window ]
	    firstResponder ] isEqual: [ self controlView ]] ) {
	color = [ NSColor whiteColor ];
    } else {
	color = [ NSColor blackColor ];
    }
    [ attributes setObject: color forKey: NSForegroundColorAttributeName ];
    
    [[ self stringValue ] drawInRect: drawFrame
	    withAttributes: attributes ];
}

- ( void )drawWithFrame: ( NSRect )cellFrame inView: ( NSView * )controlView
{
    if ( image != nil ) {
        NSSize			imageSize;
        NSRect			imageFrame;
        
        imageSize = [ image size ];
        NSDivideRect( cellFrame, &imageFrame, &cellFrame, ( imageSize.width + 5 ), NSMinXEdge );
        imageFrame.origin.x += 1;
        imageFrame.size = imageSize;
        

        if ( [ controlView isFlipped ] ) {
            imageFrame.origin.y += ceil(( NSHeight( cellFrame ) + NSHeight( imageFrame )) / 2 );
        } else {
            imageFrame.origin.y += ceil(( NSHeight( cellFrame ) - NSHeight( imageFrame )) / 2 );
        }

        [ image compositeToPoint: imageFrame.origin operation: NSCompositeSourceOver ];
    }
    
    [ super drawWithFrame: cellFrame inView: controlView ];
}

- ( NSSize )cellSize
{
    NSSize 		cellSize = [ super cellSize ];
    cellSize.width += ( image ? [ image size ].width : 0 ) + 5;
    return( cellSize );
}

@end
