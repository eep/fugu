#import <Cocoa/Cocoa.h>

@interface SFTPItemCell : NSTextFieldCell {
@private
    NSImage	*image;

}

- ( void )italicizeStringValue;
- ( void )setImage:( NSImage * )anImage;
- ( NSImage * )image;

- ( void )drawWithFrame: ( NSRect )cellFrame inView: ( NSView * )controlView;
- ( NSSize )cellSize;

@end
