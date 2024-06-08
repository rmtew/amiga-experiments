r"""
py run.py <IPC command sequence>

Put the literal text "\n" in the argument to break up into consecutive IPC commands.

e.g py run.py DBG w 0 bfec01 1 r\nDBG w 0\nipc_quit

From https://github.com/tonioni/WinUAE/blob/master/inputevents.def
e.g. py run.py evt AKS_SOFTRESET 1
e.g. py run.py evt AKS_STATERESTOREQUICK 1
e.g. py run.py evt SPC_SOFTRESET 1

With YOU replaced with your user name:
py run.py cfg statefile \"C:\Users\YOU\OneDrive\Documents\Amiga\WinUAE\States\captive 01 - planet.uss\"\nevt AKS_STATERESTOREQUICK 1
"""

import sys
import traceback
from typing import Any
import win32api, win32event, win32file, win32pipe, winerror, pywintypes

PIPENAME = r"\\.\pipe\WinUAE"

STATUS_BUFFER_OVERFLOW = 0x80000005 # ERROR_INSUFFICIENT_BUFFER


class State:
    hEventRead:     int = 0
    hEventWrite:    int = 0
    ov_read:        Any = None
    ov_write:       Any = None
    hPipe:          pywintypes.HANDLEType|None = None
    pending_events: list[int]
    read_buffer:    bytearray
    write_text:     str
    command_index:  int = 0

def process_incoming_message(state: State, text: str) -> None:
    if text == "501":
        print(f"WinUAE: unknown mode: '{state.write_text}'")
    elif text == "404":
        # Only DBG has output so this just indicates the command was passed through for non DBG.
        print(f"WinUAE: ???: '{state.write_text}'")
    else:
        print(f"WinUAE: {text}")

def write_message(state: State, text: str) -> None:
    win32event.ResetEvent(state.hEventWrite)
    state.ov_write = pywintypes.OVERLAPPED()
    state.ov_write.hEvent = state.hEventWrite
    result_value, result_text = win32file.WriteFile(state.hPipe, text.encode(), state.ov_write)
    if result_value == winerror.ERROR_IO_PENDING:
        state.pending_events.append(state.hEventWrite)
        state.ov_write = None
    state.write_text = text
    return True

def read_message(state: State) -> bool:
    win32event.ResetEvent(state.hEventRead)
    ov_read = pywintypes.OVERLAPPED()
    ov_read.hEvent = state.hEventRead
    state.read_buffer = bytearray(512)
    try:
        result_value, result_text = win32file.ReadFile(state.hPipe, state.read_buffer, ov_read)
    except pywintypes.error as e:
        if e.args[0] == winerror.ERROR_PIPE_NOT_CONNECTED:
            print("WinUAE pipe disconnected.")
            return False
    if result_value == winerror.ERROR_IO_PENDING:
        state.pending_events.append(state.hEventRead)
        state.ov_read = ov_read
    else:
        process_incoming_message(state, result_text)
    return True

def check_pipe_connected(state: State) -> bool:
    try:
        (lpFlags, lpOutBufferSize, lpInBufferSize, lpMaxInstances) = \
            win32pipe.GetNamedPipeInfo(state.hPipe)
    except pywintypes.error as e:
        if e.args[0] == winerror.ERROR_PIPE_NOT_CONNECTED:
            print("Pipe no longer connected.")
        else:
            print(f"Error: unexpected GetNamedPipeInfo error {e.args}")
        return False
    return True

def manage_pipe_connection(state : State, ipc_commands: list[str]) -> None:
    state.hEventRead = win32event.CreateEvent(None, 1, 0, None)
    state.hEventWrite = win32event.CreateEvent(None, 1, 0, None)
    state.pending_events = []

    try:
        state.hPipe = win32file.CreateFile(PIPENAME,
            win32file.GENERIC_READ | win32file.GENERIC_WRITE, 0, None, win32file.OPEN_EXISTING,
            win32file.FILE_FLAG_OVERLAPPED, None)
    except pywintypes.error as e:
        if e.args[0] == winerror.ERROR_FILE_NOT_FOUND:
            print("WinUAE pipe not found.")
        else:
            print(f"Error: unexpected CreateFile error {e.args}")
        return

    # win32pipe.SetNamedPipeHandleState(state.hPipe, win32pipe.PIPE_READMODE_MESSAGE, None, None)

    if not read_message(state):
        return
    if not write_message(state, ipc_commands[0]):
        return
    command_index = 1

    is_responding = True
    while True:
        if len(state.pending_events) == 0:
            if command_index < len(ipc_commands):
                if not read_message(state):
                    break
                if not write_message(state, ipc_commands[command_index]):
                    break
                command_index += 1
            elif command_index == len(ipc_commands):
                print("All commands executed.")
                command_index += 1
            if command_index >= len(ipc_commands) and not check_pipe_connected(state):
                return
            win32api.Sleep(1000)
            continue

        rc = win32event.WaitForMultipleObjects(state.pending_events, 0, 1000)
        if rc == win32event.WAIT_FAILED:
            print("Error: WaitForMultipleObjects: wait failed.")
            return
        elif rc == win32event.WAIT_TIMEOUT:
            if is_responding:
                print("Waiting for WinUAE to start responding again...")
            is_responding = False
            continue
        is_responding = True

        if rc >= win32event.WAIT_ABANDONED_0:
            idx = rc - win32event.WAIT_ABANDONED_0
            hEvent = state.pending_events[idx]
            if hEvent == state.hEventRead:
                state.pending_events.remove(state.hEventRead)
                print("Error: read abandoned.")
            elif hEvent == state.hEventWrite:
                state.pending_events.remove(state.hEventWrite)
                print("Error: write abandoned.")
        else:
            idx = rc - win32event.WAIT_OBJECT_0
            hEvent = state.pending_events[idx]
            if hEvent == state.hEventRead:
                read_length = state.ov_read.InternalHigh
                if state.ov_read.InternalHigh == STATUS_BUFFER_OVERFLOW:
                    text = state.read_buffer.decode()
                elif read_length == 1: # Send 'ipc_quit' as sole command.
                    assert state.read_buffer[read_length-1] == 0
                    text = ""
                elif state.read_buffer[read_length-1] == 0:
                    assert state.read_buffer[read_length-2] != 0
                    text = state.read_buffer[:read_length-1].decode()
                else:
                    print(f"Error: unexpected read result")
                    for i in range(3):
                        print(f"{i}: '{state.read_buffer[i]}'")
                    return
                state.pending_events.remove(state.hEventRead)
                state.ov_read = None
                if len(text) > 0:
                    process_incoming_message(state, text)
            elif hEvent == state.hEventWrite:
                state.pending_events.remove(state.hEventWrite)


def pipe_client(ipc_commands: list[str]) -> None:
    running = True
    while running:
        running = False
        state = State()
        try:
            manage_pipe_connection(state, ipc_commands)
        except KeyboardInterrupt:
            print("** Keyboard interrupt.")
        except pywintypes.error as e:
            traceback.print_exc()

        if state.hEventRead:
            win32file.CloseHandle(state.hEventRead)
        if state.hEventWrite:
            win32file.CloseHandle(state.hEventWrite)
        if state.hPipe:
            win32file.CloseHandle(state.hPipe)


if __name__ == '__main__':
    if len(sys.argv) == 1:
        print(f"{sys.argv[0]} <winuae IPC commands>")
        sys.exit(0)

    ipc_command = " ".join(sys.argv[1:])
    ipc_commands = ipc_command.split(r"\n")
    pipe_client(ipc_commands)
