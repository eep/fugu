#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include "ODBEditorSuite.h"

int	aesend( char *path, OSType eventType, char *sendertoken );
void	odb_close( char *path );
void	odb_save( char *path, char *sendertoken );
