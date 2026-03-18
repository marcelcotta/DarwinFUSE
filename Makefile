#
# DarwinFUSE — Userspace FUSE for macOS via NFSv4 loopback
#
# Targets:
#   all        Build static and dynamic libraries (default)
#   static     Build libdarwinfuse.a only
#   dylib      Build libdarwinfuse.dylib only
#   examples   Build example programs
#   install    Install headers + libraries + macFUSE-compatible symlinks
#   uninstall  Remove installed files
#   pkg        Build macOS .pkg installer
#   clean      Remove build artifacts
#

CC      ?= cc
AR      ?= ar
RANLIB  ?= ranlib
PREFIX  ?= /usr/local
VERSION ?= 1.0.0

# dylib versioning — match macFUSE's libfuse.2.dylib scheme so that
# existing binaries compiled against macFUSE find us at the same path.
DYLIB_COMPAT_VERSION  ?= 12.0.0
DYLIB_CURRENT_VERSION ?= 12.9.0

CFLAGS  += -Wall -Wextra -Wno-unused-parameter -std=c11 \
           -Iinclude -Isrc -D_FILE_OFFSET_BITS=64

ifeq ($(DEBUG),1)
    CFLAGS += -g -DDEBUG
else
    CFLAGS += -O2
endif

# ---- Library sources ----

LIB_SRCS := \
	src/nfs4_xdr.c \
	src/rpc.c \
	src/nfs4_server.c \
	src/nfs4_ops.c \
	src/inode_table.c \
	src/fuse_opt.c \
	src/darwinfuse.c

LIB_OBJS     := $(LIB_SRCS:.c=.o)
LIB_PIC_OBJS := $(LIB_SRCS:.c=.pic.o)

STATIC_LIB := libdarwinfuse.a
DYLIB      := libdarwinfuse.2.dylib
DYLIB_LINK := libdarwinfuse.dylib

# ---- Examples ----

EXAMPLES := examples/hello

# ---- Rules ----

.PHONY: all static dylib examples install uninstall pkg clean

all: $(STATIC_LIB) $(DYLIB)

static: $(STATIC_LIB)

dylib: $(DYLIB)

$(STATIC_LIB): $(LIB_OBJS)
	@echo "  AR    $@"
	$(AR) rcs $@ $(LIB_OBJS)
	$(RANLIB) $@

# Position-independent objects for dylib
%.pic.o: %.c
	@echo "  CC    $< (PIC)"
	$(CC) $(CFLAGS) -fPIC -c $< -o $@

$(DYLIB): $(LIB_PIC_OBJS)
	@echo "  DYLIB $@"
	$(CC) -dynamiclib -o $@ $(LIB_PIC_OBJS) \
	    -install_name $(PREFIX)/lib/libfuse.2.dylib \
	    -compatibility_version $(DYLIB_COMPAT_VERSION) \
	    -current_version $(DYLIB_CURRENT_VERSION)
	ln -sf $(DYLIB) $(DYLIB_LINK)

%.o: %.c
	@echo "  CC    $<"
	$(CC) $(CFLAGS) -c $< -o $@

examples: $(STATIC_LIB) $(EXAMPLES)

examples/hello: examples/hello.c $(STATIC_LIB)
	@echo "  CC    $@"
	$(CC) $(CFLAGS) -o $@ $< -L. -ldarwinfuse

# ---- Install / Uninstall ----

install: $(STATIC_LIB) $(DYLIB)
	@echo "Installing DarwinFUSE to $(PREFIX)..."
	install -d $(PREFIX)/lib $(PREFIX)/lib/pkgconfig \
	           $(PREFIX)/include/fuse $(PREFIX)/include/darwinfuse
	# Static library
	install -m 644 $(STATIC_LIB) $(PREFIX)/lib/
	# Dynamic library — installed as libfuse.2.dylib for macFUSE compat
	install -m 755 $(DYLIB) $(PREFIX)/lib/libfuse.2.dylib
	ln -sf libfuse.2.dylib $(PREFIX)/lib/libfuse.dylib
	ln -sf libfuse.2.dylib $(PREFIX)/lib/libdarwinfuse.2.dylib
	ln -sf libfuse.2.dylib $(PREFIX)/lib/libdarwinfuse.dylib
	# Headers — fuse/ namespace (macFUSE compatible path)
	install -m 644 include/fuse.h $(PREFIX)/include/fuse/fuse.h
	install -m 644 include/fuse_opt.h $(PREFIX)/include/fuse/fuse_opt.h
	install -m 644 include/fuse_common.h $(PREFIX)/include/fuse/fuse_common.h
	# Headers — darwinfuse/ namespace
	install -m 644 include/fuse.h $(PREFIX)/include/darwinfuse/fuse.h
	install -m 644 include/fuse_opt.h $(PREFIX)/include/darwinfuse/fuse_opt.h
	# Top-level fuse.h wrapper (macFUSE compatible)
	printf '%s\n' '#include "fuse/fuse.h"' > $(PREFIX)/include/fuse.h
	# pkg-config — darwinfuse.pc
	sed -e 's|@PREFIX@|$(PREFIX)|' -e 's|@VERSION@|$(VERSION)|' \
	    darwinfuse.pc.in > $(PREFIX)/lib/pkgconfig/darwinfuse.pc
	# pkg-config — fuse.pc (macFUSE compatible)
	sed -e 's|@PREFIX@|$(PREFIX)|' -e 's|@VERSION@|$(VERSION)|' \
	    fuse.pc.in > $(PREFIX)/lib/pkgconfig/fuse.pc
	@echo "DarwinFUSE installed successfully."

uninstall:
	@echo "Removing DarwinFUSE from $(PREFIX)..."
	rm -f  $(PREFIX)/lib/libdarwinfuse.a
	rm -f  $(PREFIX)/lib/libfuse.2.dylib
	rm -f  $(PREFIX)/lib/libfuse.dylib
	rm -f  $(PREFIX)/lib/libdarwinfuse.2.dylib
	rm -f  $(PREFIX)/lib/libdarwinfuse.dylib
	rm -rf $(PREFIX)/include/darwinfuse
	rm -rf $(PREFIX)/include/fuse
	rm -f  $(PREFIX)/include/fuse.h
	rm -f  $(PREFIX)/lib/pkgconfig/darwinfuse.pc
	rm -f  $(PREFIX)/lib/pkgconfig/fuse.pc
	@echo "DarwinFUSE removed."

# ---- .pkg installer ----

pkg: $(STATIC_LIB) $(DYLIB)
	@installer/build_pkg.sh "$(VERSION)"

# ---- Clean ----

clean:
	rm -f $(LIB_OBJS) $(LIB_PIC_OBJS) $(LIB_OBJS:.o=.d) \
	      $(STATIC_LIB) $(DYLIB) $(DYLIB_LINK) $(EXAMPLES)
