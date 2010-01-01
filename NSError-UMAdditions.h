#import <Cocoa/Cocoa.h>

@interface NSError(UMAdditions)

+ ( int )displayErrorWithDomain: ( NSString * )domain
	    code: ( int )code userInfo: ( NSDictionary * )userInfo
	    errorFormat: ( NSString * )format arguments: ( va_list )val;
+ ( int )displayError: ( NSString * )format, ...;

@end
