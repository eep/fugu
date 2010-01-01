/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#import "NSSet(ImageExtensions).h"

@implementation NSSet(ImageExtensions)

+ ( NSSet * )validImageExtensions
{
    NSSet		*set = [ NSSet setWithObjects:
                                        @"bmp", @"gif",
                                        @"icns", @"ico",
                                        @"jpg", @"jpeg",
                                        @"jp2", @"qtif",
                                        @"rgb", @"pict",
                                        @"qti", @"tga",
                                        @"targa", @"sgi",
                                        @"mac", @"pnt",
                                        @"pntg", @"fpix",
                                        @"fpx", @"cur",
                                        @"fax", @"pdf",
                                        @"png", @"psd",
                                        @"tif", @"tiff", nil ];
                                        
    return( set );
}

@end
