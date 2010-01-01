#import "UMArrayController.h"

@implementation UMArrayController

- ( id )init
{
    self = [ super init ];
    
    if ( self ) {
	_umSearchTerm = nil;
    }
    
    return( self );
}

- ( NSString * )searchTerm
{
    return( _umSearchTerm );
}

- ( void )setSearchTerm: ( NSString * )searchTerm
{
    if ( _umSearchTerm != nil ) {
	[ _umSearchTerm release ];
	_umSearchTerm = nil;
    }
    
    if ( searchTerm ) {
	_umSearchTerm = [ searchTerm retain ];
    }
}

/* NSSearchField-related methods */
- ( void )search: ( id )sender
{
    if ( ![ sender isKindOfClass: [ NSSearchField class ]]) {
	return;
    }
    
    [ self setSearchTerm: [ sender stringValue ]];
    [ self rearrangeObjects ];
}

/* XXX will probably have to add features here as needed */
- ( NSArray * )arrangeObjects: ( NSArray * )objects
{
    NSMutableArray	*alternateObjects;
    NSAutoreleasePool	*pool;
    NSString		*lowercaseTerm, *lowercaseString;
    int			i;
    
    if ( [ self searchTerm ] == nil || [[ self searchTerm ] isEqualToString: @"" ] ) {
	return( [ super arrangeObjects: objects ] );
    }
    
    lowercaseTerm = [[ self searchTerm ] lowercaseString ];

    alternateObjects = [ NSMutableArray arrayWithCapacity: [ objects count ]];
    pool = [[ NSAutoreleasePool alloc ] init ];
    for ( i = 0; i < [ objects count ]; i++ ) {
	id		obj = [ objects objectAtIndex: i ];
	
	if ( i && ( i % 20 == 0 )) {
	    [ pool release ];
	    pool = [[ NSAutoreleasePool alloc ] init ];
	}
	
	lowercaseString = [[ obj valueForKeyPath: @"hostid" ] lowercaseString ];
	if ( [ lowercaseString rangeOfString: lowercaseTerm ].location != NSNotFound ) {
	    [ alternateObjects addObject: obj ];
	    continue;
	}
	
	lowercaseString = [[ obj valueForKeyPath: @"keytype" ] lowercaseString ];
	if ( [ lowercaseString rangeOfString: lowercaseTerm ].location != NSNotFound ) {
	    [ alternateObjects addObject: obj ];
	    continue;
	}
	
	lowercaseString = [[[ obj valueForKeyPath: @"key" ]
			    string ] lowercaseString ];
	if ( [ lowercaseString rangeOfString: lowercaseTerm ].location != NSNotFound ) {
	    [ alternateObjects addObject: obj ];
	    continue;
	}
    }
    [ pool release ];
    
    return( [ super arrangeObjects: alternateObjects ] );
}

@end
