

#import "SFTPScrollView.h"


@implementation SFTPScrollView

/*
 * draw focus ring around active table
 *
 * based on code posted to cocoa-dev@lists.apple.com
 * by Nicholas Riley.
 *
 */

- ( BOOL )needsDisplay
{
    NSResponder		*r = nil;
    
    if ( [[ self window ] isKeyWindow ] ) {
        r = [[ self window ] firstResponder ];
        
        if ( r == last ) {
            return( [ super needsDisplay ] );
        }
    } else if ( last == nil ) {
        return( [ super needsDisplay ] );
    }

    shouldDrawFocusRing = (( r != nil )
                            && [ r isKindOfClass: [ NSView class ]]
                            && [ ( NSView * )r isDescendantOf: self ] );

    last = r;
    [ self setKeyboardFocusRingNeedsDisplayInRect: [ self bounds ]];  
    return( YES );
}

- ( void )drawRect: ( NSRect )rect
{
    [ super drawRect: rect ];
    if ( shouldDrawFocusRing ) {
        NSSetFocusRingStyle( NSFocusRingOnly );
        NSRectFill( [ self bounds ] );
    }
}

@end
