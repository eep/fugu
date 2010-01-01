/*
 * Copyright (c) 2005 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SFTPPrefTableView.h"

@implementation SFTPPrefTableView

/* workaround for tablecolumn bug, which always draws its cells' backgrounds */
- ( void )awakeFromNib
{
    NSTextFieldCell		*cell = [[ NSTextFieldCell alloc ] init ];
    NSArray			*columns = [ self tableColumns ];
    int				i;
    
    [ cell setDrawsBackground: NO ];
    [ cell setEditable: YES ];
    
    for ( i = 0; i < [ columns count ]; i++ ) {
        [[ columns objectAtIndex: i ] setDataCell: cell ];
    }
    [ cell release ];
}

- ( void )textDidEndEditing: ( NSNotification * )aNotification
{
    NSNotification		*notification = nil;
    int				tm = [[[ aNotification userInfo ]
                                            objectForKey: @"NSTextMovement" ] intValue ];
    
    if ( tm == NSReturnTextMovement ) {
        NSMutableDictionary	*dict = [ NSMutableDictionary dictionaryWithDictionary:
                                            [ aNotification userInfo ]];
                                            
        [ dict setObject: [ NSNumber numberWithInt: NSIllegalTextMovement ]
                        forKey: @"NSTextMovement" ];

        notification = [ NSNotification notificationWithName: [ aNotification name ]
                                        object: [ aNotification object ]
                                        userInfo: dict ];
    } else {
        notification = aNotification;
    }
    
    [ super textDidEndEditing: notification ];
    if ( tm != NSTabTextMovement ) {
        [[ self window ] makeFirstResponder: self ];
    }
}

@end
