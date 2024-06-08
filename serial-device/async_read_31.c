/*
This code is intended to process incoming serial data in a clean OS friendly
way. This yields to the OS until something wakes it up. The "nothing happened"
timer, incoming serial data or the user pressing Control-C. It is an
experiment in learning how this works, changing the approach is a fail,
working out why it doesn't work is a success. For now this has a failure in
it's "Flaw #1".

Flaw #1: There are three events. If we awaken from the timer, then the signal
is cleared. If we awaken from a serial event, then the timer cannot be
cancelled and its signal leaks and we infinite loop immediately reawakening
because nothing can clear it. What is the correct way to cancel and reuse a
timer? No idea, and no-one on EAB was able to define the correct way to do
this - just that manually clearing the signal was wrong. The timer can be
disabled using the define as a workaround.

Flaw #2: The input processing can only handle one new line in each segment of
processed text. It will pass through any excess ones for now. Whatever is
sending the text can factor this in as a workaround.
*/

#include <dos/dos.h>
#include <exec/types.h>
#include <exec/memory.h>
#include <exec/io.h>
#include <devices/serial.h>
#include <clib/exec_protos.h>
#include <clib/alib_protos.h>
#include <stdio.h>

#define USE_TIMER

void serial_read(struct IOExtSer *);
void parse_incoming_data(char *, ULONG);

/* Disable Control-C handling. */
void _chkabort(void) {}

#define SERIAL_RB_SIZE 50
char serial_rb[SERIAL_RB_SIZE+1] = "\0";
#define SERIAL_LB_SIZE 255    
char serial_lb[SERIAL_LB_SIZE+1] = "\0";
int serial_lb_index = 0;
int serial_lb_drop = 0;

/*
struct serial_state {}
*/

int main() {
    struct MsgPort *serial_port = NULL;
    struct MsgPort *console_port = NULL;
    struct IOExtSer *SerialIO = NULL;
#ifdef USE_TIMER
    struct MsgPort *timer_port = NULL;
    struct timerequest *time_request = NULL;
    LONG timer_signal;
#endif /* USE_TIMER */
    ULONG wait_signals = 0;
    LONG serial_signal;
    int err;
    int serial_device_open = 0;
    int serial_io_pending = 0;
    int running = 1;

    console_port = (struct MsgPort *)GetConsoleTask();
    if (console_port == NULL) {
        printf("Error: Unable to get console task.\n");
        goto done;
    }

#ifdef USE_TIMER
    timer_port = CreatePort(NULL, 0);
    if (!timer_port) {
        printf("Error: Failed creating timer port.\n");
        goto done;
    }

    time_request = (struct timerequest *)CreateExtIO(timer_port,
        sizeof(struct timerequest));
    if (time_request == NULL) {
        printf("Error: Failed creating time request.\n");
        goto done;
    }

    if (err = OpenDevice(TIMERNAME, UNIT_MICROHZ,
            (struct IORequest *)time_request, 0)) {
        printf("Error: Unable to open %s (%d)\n", TIMERNAME, err);
        goto done;
    }
#endif /* USE_TIMER */

    serial_port = CreateMsgPort();
    if (serial_port == NULL) {
        printf("Error: Failed creating serial port.\n");
        goto done;
    }

    SerialIO = (struct IOExtSer *)CreateExtIO(serial_port,
        sizeof(struct IOExtSer));
    if (SerialIO == NULL) {
        printf("Error: Failed creating serial IO.\n");
        goto done;
    }

    if (err = OpenDevice(SERIALNAME,0,(struct IORequest *)SerialIO,0L)) {
                if (err == 1)  
	          printf("Error: %s is in use\n", SERIALNAME);
                else
                    printf("Error: %s did not open (%d)\n",SERIALNAME, err);
        goto done;
    }

    serial_device_open = 1;

    wait_signals = SIGBREAKF_CTRL_C;
#ifdef USE_TIMER
    timer_signal = 1L << timer_port->mp_SigBit;
    wait_signals |= timer_signal;
#endif /* USE_TIMER */
    serial_signal = 1L << serial_port->mp_SigBit;
    wait_signals |= serial_signal;

    while (running > 0) {
        ULONG signals;

#ifdef USE_TIMER
        printf("Timer sendio %08lx\n", timer_signal);
        signals = SetSignal(0L, 0L);
        if ((signals & timer_signal) != 0) {
            printf("Leaked timer signal\n");
	SetSignal(0L, timer_signal); /* Hmmm */
        }
	time_request->tr_node.io_Command = TR_ADDREQUEST;
        time_request->tr_time.tv_secs = 5;
        time_request->tr_time.tv_micro = 0;
        SendIO((struct IORequest *)time_request);
#endif /* USE_TIMER */

        if (serial_io_pending == 0) {
            printf("Serial sendio %08lx\n", serial_signal);
            SerialIO->IOSer.io_Command = CMD_READ;
            SerialIO->IOSer.io_Data    = (APTR)&serial_rb;
            SerialIO->IOSer.io_Length  = 1;
            SendIO((struct IORequest *)SerialIO);
            serial_io_pending = 1;
        }

        signals = Wait(wait_signals);

        if (signals & SIGBREAKF_CTRL_C) {
            printf("ctrl-c\n");
            running = 0;
        }
        if (signals & serial_signal && CheckIO((struct IORequest *)SerialIO)) {
            printf("Waiting for serial io\n");
            WaitIO((struct IORequest *)SerialIO);
            serial_rb[1] = '\0';
            printf("Serial read '%s'\n", serial_rb);
            serial_read(SerialIO);
            serial_io_pending = 0;
        }

#ifdef USE_TIMER
        
        if ((signals & timer_signal) == 0 || !CheckIO((struct IORequest *)time_request)) {
            printf("timer abort %08lx\n", signals);
            AbortIO((struct IORequest *)time_request);
        }
        WaitIO((struct IORequest *)time_request);
#endif
    }

done:
    printf("Exiting..\n");
    if (SerialIO != NULL) {
        if (serial_io_pending) {
            AbortIO((struct IORequest *)SerialIO);
            WaitIO((struct IORequest *)SerialIO);
        }
        if (serial_device_open)
            CloseDevice((struct IORequest *)SerialIO);
        DeleteExtIO((struct IORequest *)SerialIO);
    }
    if (serial_port != NULL)
        DeleteMsgPort(serial_port);
#ifdef USE_TIMER
    if (time_request != NULL)
        CloseDevice((struct IORequest *)time_request);
    if (timer_port != NULL)
        DeleteMsgPort(timer_port);
#endif /* USE_TIMER */
}

void serial_read(struct IOExtSer *SerialIO) {
    ULONG read_size;

    /* Parse the leading character from the blocking read. */
    printf("Pre-read for serial buffer size: 1\n");
    parse_incoming_data(serial_rb, 1);

    SerialIO->IOSer.io_Command = SDCMD_QUERY;
    DoIO((struct IORequest *)SerialIO);

    read_size = SerialIO->IOSer.io_Actual;
    printf("Post-read for serial buffer size: %lu\n", read_size);
    if (read_size > 50)
        read_size = 50;

    if (read_size > 0) {    
        SerialIO->IOSer.io_Length = read_size;
        SerialIO->IOSer.io_Data = (APTR)&serial_rb;
        SerialIO->IOSer.io_Command = CMD_READ;
        DoIO((struct IORequest *)SerialIO);

        parse_incoming_data(serial_rb, read_size);
    }
} /* serial_read() */

void parse_incoming_data(char *buffer_in, ULONG read_size) {
    char *match_p;
    size_t copy_count = 0;

    serial_rb[read_size] = '\0';
    match_p = (char *)strchr(serial_rb, '\n');
    if (match_p == NULL)
        copy_count = read_size;
    else
        copy_count = match_p - serial_rb;         
    if (serial_lb_index + copy_count > SERIAL_LB_SIZE) {
        printf("dropping random text due to buffer length.\n");
        serial_lb_drop += serial_lb_index + copy_count;
        serial_lb_index = 0;
    } else if (copy_count > 0) {
        strncat(serial_lb, serial_rb, copy_count);
        serial_lb_index += copy_count;
        serial_lb[serial_lb_index] = 0;
    }
    if (match_p != NULL) {
        size_t remainder = read_size - copy_count;
        if (serial_lb_drop > 0) {
            printf("discarding long line %d\n", serial_lb_drop);
            serial_lb_drop = 0;
        } else {
            printf("processing line '%s'\n", serial_lb);
        }

        if (remainder > 1) {
            memcpy(serial_lb, serial_rb + copy_count + 1, remainder - 1);
            serial_lb_index = remainder - 1; 
            printf("aaa %lu\n", remainder - 1);
        } else
            serial_lb_index = 0;
        serial_lb[serial_lb_index] = '\0';
    }
} /* serial_read() */
