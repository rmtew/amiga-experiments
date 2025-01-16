# Serial ports

These were intended to experiment with controlling WinUAE when the serial port
is configured to be exposed on an external socket.

Host -> IO ports -> Serial port, set the dropdown to HTTP://127.0.0.1:1234

## Arexx: serial-reader.rexx

This opens the serial port and reads characters until it has a complete line.
A flaw with the approach is that the control-C signal is not handled until
`READCH` receives something new.

Thomas Richter [points out](https://eab.abime.net/showpost.php?p=1687792&postcount=4)
that there is a `NOWAIT` option in the port handler from AmigaDOS 45 onward
(3.2). However, if the goal is for a solution to work in 1.2, 1.3 or even 3.1
this is a limiting option.

## C: async_read_31.c

This achieves the desired goals:

#. Yield to the OS until something the application is interested in happens.
#. Read a line from the serial device.
#. Exit cleanly ensuring the serial device is reusable.

There are some niggling flaws however:

* The text processing can only handle one `\n` in an incoming string and
  will let additional ones slip through messing up what will be processed.
  This is easily avoided by only sending one command at a time.
* The timer is reset every loop. This leaks a signal and will mean the
  yield will always immediately return. Clearing the signal manually is
  the only way to deal with this and [discussions on EAB](https://eab.abime.net/showthread.php?t=117721)
  resulted in no clarity. Seems like a bug in the OS to me.

