#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <getopt.h>

#include "hidapi.h"

#define ZMK_HAPTIC_HID_REPORT_ID 0x04
#define ZMK_HAPTIC_FORCE 128
#define ZMK_HAPTIC_DURATION_MS 20

#define MAX_STR 1024  // for manufacturer, product strings
#define OFFLIST_LEN 2
float offList[OFFLIST_LEN][2] = {
    {4.0, 2.0},
    {7.5, 12.0}
};

static void print_usage(char *myname)
{
    fprintf(stderr,
"Usage: \n"
"  %s <cmd> [options]\n"
"where <cmd> is one of:\n"
"  --serial <string>           Filter by serial number \n"
"  --list-detail               List HID devices w/ details (by filters)\n"
"  --start-haptic-cursor       Start monitoring you cursor and send report to ZMK device\n"
"\n"
"Notes: \n"
" . Commands are executed in order. \n"
" . --vidpid, --usage, --usagePage, --serial act as filters to --open and --list \n"
"\n"
"Examples: \n"
". List all devices \n"
"   hidapitester --list \n"
". Search the ZMK device with haptic feedback enabling, find the serial number \n"
". Start haptic cursur state \n"
"   hidapitester --serial 0D7FEFEE68D8C54D --open --start-haptic-cursor \n"
". If see 'Error: could not open device', open 'System Settings -> Security' and \n"
"  grant the permissoin to Termianl. And run it again with 'sudo' \n"
"\n"
""
"", myname);
}

// local states for the "cmd" option variable
enum {
    CMD_NONE = 0,
    CMD_SERIALNUMBER,
    CMD_LIST_DETAIL,
    CMD_START_HAPTIC_CURSOR,
};

void msg(char* fmt, ...)
{
    va_list args;
    va_start(args,fmt);
    vprintf(fmt,args);
    va_end(args);
}

int main(int argc, char* argv[])
{
    hid_device *dev = NULL; // HIDAPI device we will open
    int res;
    int i;
    int cmd = CMD_NONE;     //

    wchar_t serial_wstr[MAX_STR/4] = {L'\0'}; // serial number string rto search for, if any
    char devpath[MAX_STR];   // path to open, if filter by usage

    setbuf(stdout, NULL);  // turn off buffering of stdout

    if(argc < 2){
        print_usage( "hidapitester" );
        exit(1);
    }

    struct option longoptions[] =
        {
         {"serial",       required_argument, &cmd,   CMD_SERIALNUMBER},
         {"list",  no_argument,       &cmd,   CMD_LIST_DETAIL},
         {"start-haptic-cursor", no_argument, &cmd, CMD_START_HAPTIC_CURSOR},
         {NULL,0,0,0}
        };
    char* shortopts = "vht:l:qb:";

    bool done = false;
    int option_index = 0, opt;
    while(!done) {
        memset(devpath,0,MAX_STR);

        opt = getopt_long(argc, argv, shortopts, longoptions, &option_index);
        if (opt==-1) done = true; // parsed all the args
        switch(opt) {
        case 0:                   // long opts with no short opts

            if( cmd == CMD_SERIALNUMBER ) {
                swprintf( serial_wstr, sizeof(serial_wstr), L"%s", optarg); // convert to wchar_t*
            }
            else if( cmd == CMD_LIST_DETAIL ) {

                struct hid_device_info *devs, *cur_dev;
                devs = hid_enumerate(0,0); // 0,0 = find all devices
                cur_dev = devs;
                while (cur_dev) {
                    if( (serial_wstr[0]==L'\0' || wcscmp(cur_dev->serial_number, serial_wstr)==0) ) {
                        printf("%04X/%04X: %ls - %ls\n",
                                cur_dev->vendor_id, cur_dev->product_id,
                                cur_dev->manufacturer_string, cur_dev->product_string );
                        if( cmd == CMD_LIST_DETAIL ) {
                            // printf("  vendorId:      0x%04hX\n", cur_dev->vendor_id);
                            // printf("  productId:     0x%04hX\n", cur_dev->product_id);
                            printf("  serial_number: %ls \n", cur_dev->serial_number);
                            printf("\n");
                        }
                    }
                    cur_dev = cur_dev->next;
                }
                hid_free_enumeration(devs);
            }
            else if( cmd == CMD_START_HAPTIC_CURSOR ) {

                struct hid_device_info *devs, *cur_dev;
                devs = hid_enumerate(0, 0); // 0,0 = find all devices
                cur_dev = devs;
                while (cur_dev) {
                    if( (serial_wstr[0]==L'\0' || wcscmp(cur_dev->serial_number, serial_wstr)==0) ) {
                        strncpy(devpath, cur_dev->path, MAX_STR); // save it!
                    }
                    cur_dev = cur_dev->next;
                }
                hid_free_enumeration(devs);

                if( devpath[0] ) {
                    dev = hid_open_path(devpath);
                    if( dev==NULL ) {
                        msg("Error: could not open device\n"); break;
                    }
                    else {
                        msg("Device opened\n");
                    }
                }
                else {
                    msg("Error: no matching devices\n"); break;
                }

                if( !dev ) {
                    msg("Error on send: no device opened.\n"); break;
                }
                for(;;) {
                    static float x, y;
                    id pool = [[NSAutoreleasePool alloc] init];
                    NSCursor *c = [NSCursor currentSystemCursor];
                    NSPoint p = [c hotSpot];
                    if(x != p.x || y != p.y) {
                        // printf("%f, %f\n", p.x, p.y);
                        x = p.x;
                        y = p.y;
                        for (int i = 0; i < OFFLIST_LEN; i++) {
                            if(x == offList[i][0] && y == offList[i][1]) {
                                // latch 0
                                continue;
                            }
                        }
                        // latch 1
                        uint8_t buf[3] = { 
                            ZMK_HAPTIC_HID_REPORT_ID,
                            ZMK_HAPTIC_FORCE, ZMK_HAPTIC_DURATION_MS
                        };
                        res = hid_write(dev, buf, 3);
                    }
                    [pool release];
                }

            }

            break; // case 0 (longopts without shortops)
        } // switch(opt)


    } // while(!done)

    if(dev) {
        msg("Closing device\n");
        hid_close(dev);
    }
    res = hid_exit();

} // main
