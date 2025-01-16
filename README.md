# Amiga Experiments

Programming challenges? Software archeology?

## WinUAE related

### serial-device

If I wanted to communicate from outside WinUAE with a running process inside WinUAE, one way to
do this is to configure it (under Settings/Host/IO ports/Serial port) to expose the emulated serial
port as a localhost address and port. In this folder are various attempts to read from the serial
port, with varying degrees of success.

See the relevant [README.md](serial-device/README.md) for further detail.

### winuae-named-pipe

WinUAE has a named pipe `\\.\pipe\WinUAE` that can be used to communicate with the emulator. In
theory it should be possible to interact with running code using this. Commands can be sent to
control both the emulator and running state and this includes the debugger.

The Python script `run.py` can be used externally on Windows to send commands to this named pipe
and view the output.
