/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "SFTPAboutPanel.h"

@implementation SFTPAboutPanel

- ( void )awakeFromNib
{
    [ creditsTextField setEditable: NO ];
}

- ( IBAction )viewReadMe: ( id )sender
{    
    /* let the default text editor do the heavy lifting */
    if ( ! [[ NSWorkspace sharedWorkspace ] openFile:
                [[ NSBundle mainBundle ] pathForResource: @"Fugu README"
                                            ofType: @"rtfd" ]] ) {
        NSRunAlertPanel( @"Failed to open Read Me file!",
                @"It seems something's wrong inside Fugu. You may want to reinstall. "
                @"You will not lose any of your settings if you choose to reinstall.",
                @"OK", @"", @"" );
        return;
    }
}

- ( IBAction )emailAuthor: ( id )sender
{
    [[ NSWorkspace sharedWorkspace ] openURL: [ NSURL URLWithString:
                                        @"mailto:fugu@umich.edu" ]];
}

- ( IBAction )visitHomePage:( id )sender
{
    [[ NSWorkspace sharedWorkspace ] openURL: [ NSURL URLWithString:
                                        @"http://rsug.itd.umich.edu/software/fugu" ]];
}

@end
