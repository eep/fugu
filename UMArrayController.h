#import <Cocoa/Cocoa.h>


@interface UMArrayController : NSArrayController
{
    NSString	    *_umSearchTerm;
}

- ( void )search: ( id )sender;

@end
