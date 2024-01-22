HIDAPI_DIR ?= ./hidapi

UNAME := $(shell uname -s)
ifeq "$(UNAME)" "Darwin"
	OS=macos
endif
ifeq "$(OS)" "macos"

CC ?= cc
CFLAGS += -arch x86_64
# CFLAGS += -arch arm64
LIBS = -framework Cocoa -framework IOKit -framework CoreFoundation -framework AppKit
OBJS_hid=$(HIDAPI_DIR)/mac/hid.o

else
	$(info ***  for macOS only  ***)
	exit
endif

CFLAGS += -I $(HIDAPI_DIR)/hidapi
OBJS += haptic-tester.mo

all: haptic-tester

$(OBJS): %.mo: %.m
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJS_hid): %.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

haptic-tester: $(OBJS) $(OBJS_hid)
	$(CC) $(CFLAGS) $(OBJS) $(OBJS_hid) -o haptic-tester $(LIBS)

clean:
	rm -f $(OBJS)
	rm -f haptic-tester
