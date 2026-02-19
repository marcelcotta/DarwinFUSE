#
# DarwinFUSE — Userspace FUSE for macOS via NFSv4 loopback
#
# Targets:
#   all        Build libdarwinfuse.a (default)
#   examples   Build example programs
#   install    Install headers + lib to PREFIX
#   clean      Remove build artifacts
#

CC      ?= cc
AR      ?= ar
RANLIB  ?= ranlib
PREFIX  ?= /usr/local
VERSION ?= 0.1.0

CFLAGS  += -Wall -Wextra -Wno-unused-parameter -std=c11 \
           -Iinclude -Isrc -D_FILE_OFFSET_BITS=64

ifeq ($(DEBUG),1)
    CFLAGS += -g -DDEBUG
else
    CFLAGS += -O2
endif

# ---- Library ----

LIB_SRCS := \
	src/nfs4_xdr.c \
	src/rpc.c \
	src/nfs4_server.c \
	src/nfs4_ops.c \
	src/inode_table.c \
	src/fuse_opt.c \
	src/darwinfuse.c

LIB_OBJS := $(LIB_SRCS:.c=.o)
LIB      := libdarwinfuse.a

# ---- Examples ----

EXAMPLES := examples/hello

# ---- Rules ----

.PHONY: all examples install clean

all: $(LIB)

$(LIB): $(LIB_OBJS)
	@echo "  AR    $@"
	$(AR) rcs $@ $(LIB_OBJS)
	$(RANLIB) $@

%.o: %.c
	@echo "  CC    $<"
	$(CC) $(CFLAGS) -c $< -o $@

examples: $(LIB) $(EXAMPLES)

examples/hello: examples/hello.c $(LIB)
	@echo "  CC    $@"
	$(CC) $(CFLAGS) -o $@ $< -L. -ldarwinfuse

install: $(LIB)
	install -d $(PREFIX)/lib $(PREFIX)/lib/pkgconfig \
	           $(PREFIX)/include/darwinfuse
	install -m 644 $(LIB) $(PREFIX)/lib/
	install -m 644 include/fuse.h $(PREFIX)/include/darwinfuse/fuse.h
	install -m 644 include/fuse_opt.h $(PREFIX)/include/darwinfuse/fuse_opt.h
	sed -e 's|@PREFIX@|$(PREFIX)|' -e 's|@VERSION@|$(VERSION)|' \
	    darwinfuse.pc.in > $(PREFIX)/lib/pkgconfig/darwinfuse.pc

clean:
	rm -f $(LIB_OBJS) $(LIB_OBJS:.o=.d) $(LIB) $(EXAMPLES)
