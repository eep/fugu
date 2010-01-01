#import "NSError-UMAdditions.h"

@implementation NSError(UMAdditions)

+ ( int )displayErrorWithDomain: ( NSString * )domain
	    code: ( int )code userInfo: ( NSDictionary * )userInfo
	    errorFormat: ( NSString * )format arguments: ( va_list )val
{
    NSAlert		    *alert;
    NSDictionary	    *dict;
    NSError		    *error;
    NSString		    *errorString;
    
    dict = userInfo;
    if ( !dict ) {
	errorString = [[[ NSString alloc ] initWithFormat: format 
			arguments: val ] autorelease ];
	
	dict = [ NSDictionary dictionaryWithObject: errorString
		forKey: NSLocalizedDescriptionKey ];
    }
    error = [ NSError errorWithDomain: domain code: code userInfo: dict ];
    
    alert = [ NSAlert alertWithError: error ];
    return( [ alert runModal ] );
}

+ ( int )displayError: ( NSString * )format, ...


{
    va_list		    val;
    int			    rc;
    
    va_start( val, format );
    
    rc = [ NSError displayErrorWithDomain: NSCocoaErrorDomain code: 1
	    userInfo: nil errorFormat: format arguments: val ];
    va_end( val );
		
    return( rc );
}

@end
