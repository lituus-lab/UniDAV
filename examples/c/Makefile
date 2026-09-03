# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
# Shell-free: `pwd` and `rm` are unavailable under mingw32-make on Windows.
ifeq ($(origin CC),default)
  ifeq ($(OS),Windows_NT)
    CC := gcc
  else
    CC := cc
  endif
endif

ROOT   := $(CURDIR)/../..
CFLAGS := -I$(ROOT)/include -O2 -Wall -Wextra -std=c11
LIB    := $(ROOT)/libUniDAV.a

# What the engine's own C sources call into: WinHTTP on Windows, libcurl
# elsewhere. SQLite is loaded at run time by db_connector, so nothing links it.
ifeq ($(OS),Windows_NT)
  BIN  := demo.exe
  RUN  := $(BIN)
  RM_F := del /q
  LIBS := -lwinhttp
else
  BIN  := demo
  RUN  := ./$(BIN)
  RM_F := rm -f
  LIBS := -lcurl
endif

.PHONY: all run clean
all: run
run: $(BIN)
	$(RUN)
$(BIN): demo.c $(ROOT)/include/UniDAV.h $(LIB)
	$(CC) $(CFLAGS) -o $(BIN) demo.c $(LIB) $(LIBS)
# File target, not phony: `nimble cexample` already built the lib, don't redo it.
$(LIB):
	cd $(ROOT) && nimble clibStatic
clean:
	$(RM_F) $(BIN)
