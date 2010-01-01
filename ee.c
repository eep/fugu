#include <sys/types.h>
#include <sys/event.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "aevent.h"

extern int		errno;
extern char		**environ;

/*
 * externaleditor: edit given file in console editor;
 * on exit, prompt to upload if changes were made.
 */
    int
main( int ac, char *av[] )
{
    char		*ed[ 3 ] = { NULL, NULL, NULL };
    char		*editor = NULL;
    char		*path = NULL, *name = NULL;
    char		sendertoken[ MAXPATHLEN ];
    struct stat		st;
    int			status, answer = 0;
    pid_t		pid;
    time_t		tstamp;

    if ( ac < 3 ) {
	fprintf( stderr, "Usage: %s editor file ...\n", av[ 0 ] );
	exit( 1 );
    }

    editor = av[ 1 ];
    path = av[ 2 ];
    if (( name = basename( path )) == NULL ) {
	name = path;
    }
    
    if ( ac >= 4 ) {
	/* copy the sender token to give back to the server */
	( void )strlcpy( sendertoken, av[ 3 ], sizeof( sendertoken ));
    }

    if ( stat( path, &st ) < 0 ) {
	fprintf( stderr, "stat %s: %s\n", path, strerror( errno ));
	exit( 2 );
    }

    switch ( st.st_mode & S_IFMT ) {
    case S_IFREG:
	break;

    default:
	fprintf( stderr, "%s: not a regular file\n", path );
	exit( 1 );
    }

    tstamp = st.st_mtime;

    ed[ 0 ] = editor;
    ed[ 1 ] = path;
    ed[ 2 ] = NULL;

    switch (( pid = fork())) {
    case 0:
	execve( editor, ed, environ );
	fprintf( stderr, "execve %s failed: %s\n", editor, strerror( errno ));
	fflush( stderr );
	_exit( 2 );

    case -1:
	fprintf( stderr, "fork failed: %s\n", strerror( errno ));
	fflush( stderr );
	exit( 2 );
    
    default:
	break;
    }

    pid = wait( &status );

    if ( WEXITSTATUS( status ) != 0 ) {
	fprintf( stderr, "%s exited with %d\n", editor, WEXITSTATUS( status ));
	exit( WEXITSTATUS( status ));
    }

    if ( stat( path, &st ) < 0 ) {
	fprintf( stderr, "stat %s: %s\n", path, strerror( errno ));
	exit( 2 );
    }

    /* if mod date is newer after editing, prompt to upload */
    if ( st.st_mtime > tstamp ) {
	do {
	    printf( "\n%s was modified. Upload? (y/n) ", name );
	    answer = getchar();
	    fpurge( stdin );
	} while ( answer != 'y' && answer != 'n' );

	if ( answer == 'y' ) {
	    odb_save( path, sendertoken );
	}
    }
	    
    odb_close( path );
    return( 0 );
}
