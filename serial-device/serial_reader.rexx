/* Arexx gives a confusing error if your first line is not a comment. */
SIGNAL ON BREAK_C

IF ( ~OPEN( 'serial', 'SER:', 'R' ) ) THEN DO
    SAY 'Failed to open serial port.'
    EXIT 0
END

SAY EOF('serial')

DO FOREVER
    line = ''
    DO UNTIL ( C2D( char ) = 10 )
        char = READCH('serial')
        line = line || char
    END
    line = STRIP( line, 'T', D2C( 10 ) )
    IF line = 'exit' THEN DO 1
        CLOSE('serial')
        SAY 'Exiting due to external command'
        EXIT 0
    END
    SAY LINE
END

BREAK_C:
    SAY 'Ctrl+C.'
    EXIT 1
