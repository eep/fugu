#include "aevent.h"

/* handles sending event to server */
    int
aesend( char *path, OSType eventType, char *sendertoken )
{
    FSRef		fileref;
    FSSpec		filespec;
    AEDesc		d, appld;
    AEKeyword		signature = 'Fugu';
    AppleEvent		ae = { typeNull, NULL };
    OSErr		err = ( OSErr )0;
    OSStatus		status;

    /* convert POSIX path to FSRef, then to FSSpec */
    if (( status = FSPathMakeRef(( UInt8 * )path, &fileref, NULL )) != noErr ) {
	fprintf( stderr, "FSPathMakeRef failed: error %d", ( int )status );
	return( -1 );
    }
    if (( status = FSGetCatalogInfo( &fileref, kFSCatInfoNone,
			NULL, NULL, &filespec, NULL )) != noErr ) {
	fprintf( stderr, "FSGetCatalogInfo failed: error %d\n", ( int )status );
	return( -1 );
    }

    /* create descriptor containing Fugu's signature */
    if (( err = AECreateDesc( typeApplSignature,
		( Ptr )&signature, sizeof( signature ), &appld )) != noErr ) {
	fprintf( stderr, "AECreateDesc failed: error %d\n", ( int )err );
	return( -1 );
    }

    /* create the AppleEvent */
    if (( err = AECreateAppleEvent( kODBEditorSuite, ( AEKeyword )eventType,
		&appld, kAutoGenerateReturnID, 
		kAnyTransactionID, &ae )) != noErr ) {
	fprintf( stderr, "AECreateAppleEvent failed: error %d\n", ( int )err );
	return( -1 );
    }

    ( void )AEDisposeDesc( &appld );

    /* location of saved file */
    if (( err = AECreateDesc( typeFSS, ( Ptr )&filespec,
		sizeof( filespec ), &d )) != noErr ) {
	fprintf( stderr, "AECreateDesc failed: error %d\n", err );
	return( -1 );
    }
    
    if (( err = AEPutParamDesc( &ae, keyDirectObject, &d )) != noErr ) {
	fprintf( stderr, "AEPutParamDesc failed: error %d\n", err );
	return( -1 );
    } 
    ( void )AEDisposeDesc( &d );

    if ( sendertoken != NULL ) {
	/* include sendertoken */
	if (( err = AECreateDesc( typeChar, ( Ptr )sendertoken,
		strlen( sendertoken ), &d )) != noErr ) {
	    fprintf( stderr, "AECreateDesc failed: error %d\n", err );
	    return( -1 );
	}

	if (( err = AEPutParamDesc( &ae, keySenderToken, &d )) != noErr ) {
	    fprintf( stderr, "AEPutParamDesc failed: error %d\n", err );
	    return( -1 );
	}
	( void )AEDisposeDesc( &d );
    }

    if (( err = AESend( &ae, NULL, kAENoReply, kAENormalPriority,
				kNoTimeOut, NULL, NULL )) != noErr ) {
	fprintf( stderr, "AESend failed: error %d\n", err );
	return( -1 );
    }

    ( void )AEDisposeDesc( &ae );

    return( 0 );
}

    void
odb_save( char *path, char *sendertoken )
{
    if ( aesend( path, kAEModifiedFile, sendertoken ) < 0 ) {
	fprintf( stderr, "Failed to send save event\n" );
    }
}

    void
odb_close( char *path )
{
    if ( aesend( path, kAEClosedFile, NULL ) < 0 ) {
	fprintf( stderr, "Failed to send close event\n" );
    }
}
