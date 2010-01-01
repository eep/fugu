/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import <Cocoa/Cocoa.h>

@interface SFTPAboutPanel : NSObject
{
    IBOutlet NSButton		*emailButton;
    IBOutlet NSTextView 	*creditsTextField;
    IBOutlet NSButton 		*homepageButton;
    IBOutlet NSImageView 	*pufferIconField;
    IBOutlet NSButton 		*readMeButton;
}

- ( IBAction )viewReadMe: ( id )sender;
- ( IBAction )visitHomePage: ( id )sender;
- ( IBAction )emailAuthor: ( id )sender;

- ( void )awakeFromNib;

@end
