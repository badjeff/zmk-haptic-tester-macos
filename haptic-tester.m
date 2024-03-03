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
#define ZMK_HAPTIC_FORCE 1
#define ZMK_HAPTIC_DURATION_MS 16

@interface AppController : NSObject <NSApplicationDelegate> {
    NSRunningApplication *currentApp;
    struct hid_device_ *dev;
}
@property (retain) NSRunningApplication *currentApp;
@end

@implementation AppController 
@synthesize currentApp;
- (id)init {
    if ((self = [super init])) {
        [[[NSWorkspace sharedWorkspace] notificationCenter]
            addObserver:self selector:@selector(activeAppDidChange:)
            name:NSWorkspaceDidActivateApplicationNotification object:nil];
    }
    self.dev = NULL;
    return self;
}
- (void)setDev:(struct hid_device_ *)_dev {
    dev = _dev;
}
- (void)dealloc {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [super dealloc];
}
- (void)activeAppDidChange:(NSNotification *)notification {
    self.currentApp = [[notification userInfo] objectForKey:NSWorkspaceApplicationKey];
    NSString* bundleId = [currentApp bundleIdentifier];
    NSLog(@"%@", bundleId);
    uint8_t buf[3] = { 
        ZMK_HAPTIC_HID_REPORT_ID,
        ZMK_HAPTIC_FORCE + 1,
        ZMK_HAPTIC_DURATION_MS
    };
    hid_write(dev, buf, 3);
}
- (void)runloop:(NSObject *)userInfo {
    #define OFFLIST_LEN 2
    static float offList[OFFLIST_LEN][2] = {
        {4.0, 2.0},
        {7.5, 12.0}
    };
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
            ZMK_HAPTIC_FORCE + 0,
            ZMK_HAPTIC_DURATION_MS
        };
        hid_write(dev, buf, 3);
    }
    [pool release];
}
@end

#define MAX_STR 1024  // for manufacturer, product strings

static void print_usage(char *myname)
{
    fprintf(stderr,
"Usage: \n"
"  %s <cmd> [options]\n"
"where <cmd> is one of:\n"
"  --product <string>          Filter by product string \n"
"  --usagePage <string>        Filter by usage page \n"
"  --serial <string>           Filter by serial number \n"
"  --list                      List HID devices w/ details (by filters)\n"
"  --start                     Start monitoring you cursor and send report to ZMK device\n"
"\n"
"Notes: \n"
" . Commands are executed in order. \n"
" . --product, --usagePage, --serial act as filters to --list \n"
"\n"
"Examples: \n"
". List all devices \n"
"   haptic-tester --list \n"
". Search the ZMK device with haptic feedback enabling, find the product id and usage page \n"
". Start haptic cursor state \n"
"   haptic-tester --product ztrackball --usagePage 0xFF0C --start \n"
". If see 'Error: could not open device', open 'System Settings -> Security' and \n"
"  grant the permissoin to Termianl. And run it again with 'sudo' \n"
"\n"
""
"", myname);
}

// local states for the "cmd" option variable
enum {
    CMD_NONE = 0,
    CMD_PRODUCT,
    CMD_USAGEPAGE,
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

    uint16_t usage_page = 0; // usagePage to search for, if any
    wchar_t product_wstr[MAX_STR] = {L'\0'}; // serial number string rto search for, if any
    wchar_t serial_wstr[MAX_STR/4] = {L'\0'}; // serial number string rto search for, if any
    char devpath[MAX_STR];   // path to open, if filter by usage

    setbuf(stdout, NULL);  // turn off buffering of stdout

    if(argc < 2){
        print_usage( "haptic-tester" );
        exit(1);
    }

    struct option longoptions[] =
        {
         {"product",      required_argument, &cmd,   CMD_PRODUCT},
         {"usagePage",    required_argument, &cmd,   CMD_USAGEPAGE},
         {"serial",       required_argument, &cmd,   CMD_SERIALNUMBER},
         {"list",  no_argument,       &cmd,   CMD_LIST_DETAIL},
         {"start", no_argument, &cmd, CMD_START_HAPTIC_CURSOR},
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

            if( cmd == CMD_PRODUCT ) {
                swprintf( product_wstr, sizeof(product_wstr), L"%s", optarg); // convert to wchar_t*
            }
            else if( cmd == CMD_SERIALNUMBER ) {
                swprintf( serial_wstr, sizeof(serial_wstr), L"%s", optarg); // convert to wchar_t*
            }
            else if( cmd == CMD_USAGEPAGE ) {
                if( (usage_page = strtol(optarg,NULL,0)) == 0 ) { // if bad parse
                    sscanf(optarg, "%4hx", &usage_page ); // try bare "ABCD"
                }
            }
            else if( cmd == CMD_LIST_DETAIL ) {

                struct hid_device_info *devs, *cur_dev;
                devs = hid_enumerate(0,0); // 0,0 = find all devices
                cur_dev = devs;
                while (cur_dev) {
                    if( (!usage_page || cur_dev->usage_page == usage_page) &&
                        (product_wstr[0]==L'\0' || wcscmp(cur_dev->product_string, product_wstr)==0) &&
                        (serial_wstr[0]==L'\0' || wcscmp(cur_dev->serial_number, serial_wstr)==0)
                    ) {
                        printf("%04X/%04X: %ls - %ls\n",
                                cur_dev->vendor_id, cur_dev->product_id,
                                cur_dev->manufacturer_string, cur_dev->product_string );
                        if( cmd == CMD_LIST_DETAIL ) {
                            // printf("  vendorId:      0x%04hX\n", cur_dev->vendor_id);
                            // printf("  productId:     0x%04hX\n", cur_dev->product_id);
                            printf("  usagePage:     0x%04hX\n", cur_dev->usage_page);
                            printf("  serial_number: %ls \n", cur_dev->serial_number);
                            printf("  path: %s\n",cur_dev->path);
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
                    if( (!usage_page || cur_dev->usage_page == usage_page) &&
                        (product_wstr[0]==L'\0' || wcscmp(cur_dev->product_string, product_wstr)==0) &&
                        (serial_wstr[0]==L'\0' || wcscmp(cur_dev->serial_number, serial_wstr)==0)
                    ) {
                        strncpy(devpath, cur_dev->path, MAX_STR); // save it!
                        printf("#### >> devpath: %s \n", devpath);
                        // strncpy(devpath, "DevSrvsID:4308946121", MAX_STR); // save it!
                        // printf("#### >> devpath: %s \n", devpath);
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

                NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
                AppController *appController = [[AppController alloc] init];
                [appController setDev:dev];
                NSDate *now = [[NSDate alloc] init];
                NSTimer *timer = [[NSTimer alloc] initWithFireDate:now interval:.01
                    target:appController selector:@selector(runloop:)
                    userInfo:nil repeats:YES];
                NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
                [runLoop addTimer:timer forMode:NSDefaultRunLoopMode];
                [runLoop run]; // this shall block until timer stop
                [pool release];

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
