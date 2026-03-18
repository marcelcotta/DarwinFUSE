#
# DarwinFUSE — Userspace FUSE for macOS via NFSv4 loopback
#
# Targets:
#   all        Build universal (arm64+x86_64) static and dynamic libraries (default)
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
LIPO    ?= lipo
PREFIX  ?= /usr/local
VERSION ?= 1.0.0

# dylib versioning — match macFUSE's libfuse.2.dylib scheme so that
# existing binaries compiled against macFUSE find us at the same path.
DYLIB_COMPAT_VERSION  ?= 12.0.0
DYLIB_CURRENT_VERSION ?= 12.9.0

# Universal binary architectures
ARCHS ?= arm64 x86_64

CFLAGS_BASE := -Wall -Wextra -Wno-unused-parameter -std=c11 \
               -Iinclude -Isrc -D_FILE_OFFSET_BITS=64

ifeq ($(DEBUG),1)
    CFLAGS_BASE += -g -DDEBUG
else
    CFLAGS_BASE += -O2
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

STATIC_LIB := libdarwinfuse.a
DYLIB      := libdarwinfuse.2.dylib
DYLIB_LINK := libdarwinfuse.dylib

# ---- Per-arch build directories ----

BUILD_DIRS := $(foreach arch,$(ARCHS),build/$(arch))

# ---- Examples ----

EXAMPLES := examples/hello

# ---- Rules ----

.PHONY: all static dylib examples install uninstall pkg clean

all: $(STATIC_LIB) $(DYLIB)

static: $(STATIC_LIB)

dylib: $(DYLIB)

# Build objects for a single architecture into build/<arch>/
define ARCH_RULES
build/$(1)/%.o: %.c | build/$(1)/src
	@echo "  CC    $$< ($(1))"
	$$(CC) $$(CFLAGS_BASE) -arch $(1) -c $$< -o $$@

build/$(1)/%.pic.o: %.c | build/$(1)/src
	@echo "  CC    $$< ($(1) PIC)"
	$$(CC) $$(CFLAGS_BASE) -arch $(1) -fPIC -c $$< -o $$@

build/$(1)/src:
	@mkdir -p build/$(1)/src
endef

$(foreach arch,$(ARCHS),$(eval $(call ARCH_RULES,$(arch))))

# Per-arch object lists
ARCH_OBJS     = $(foreach src,$(LIB_SRCS),build/$(1)/$(src:.c=.o))
ARCH_PIC_OBJS = $(foreach src,$(LIB_SRCS),build/$(1)/$(src:.c=.pic.o))

# Per-arch static libraries
define ARCH_STATIC
build/$(1)/libdarwinfuse.a: $(call ARCH_OBJS,$(1))
	@echo "  AR    $$@ ($(1))"
	$$(AR) rcs $$@ $$^
	$$(RANLIB) $$@
endef

$(foreach arch,$(ARCHS),$(eval $(call ARCH_STATIC,$(arch))))

# Per-arch dylibs
define ARCH_DYLIB
build/$(1)/libdarwinfuse.2.dylib: $(call ARCH_PIC_OBJS,$(1))
	@echo "  DYLIB $$@ ($(1))"
	$$(CC) -dynamiclib -arch $(1) -o $$@ $$^ \
	    -install_name $$(PREFIX)/lib/libfuse.2.dylib \
	    -compatibility_version $$(DYLIB_COMPAT_VERSION) \
	    -current_version $$(DYLIB_CURRENT_VERSION)
endef

$(foreach arch,$(ARCHS),$(eval $(call ARCH_DYLIB,$(arch))))

# Universal static library via lipo
$(STATIC_LIB): $(foreach arch,$(ARCHS),build/$(arch)/libdarwinfuse.a)
	@echo "  LIPO  $@ ($(ARCHS))"
	$(LIPO) -create $^ -output $@

# Universal dylib via lipo
$(DYLIB): $(foreach arch,$(ARCHS),build/$(arch)/libdarwinfuse.2.dylib)
	@echo "  LIPO  $@ ($(ARCHS))"
	$(LIPO) -create $^ -output $@
	ln -sf $(DYLIB) $(DYLIB_LINK)

# Examples (universal)
examples: $(STATIC_LIB) $(EXAMPLES)

examples/hello: examples/hello.c $(STATIC_LIB)
	@echo "  CC    $@ (universal)"
	$(CC) $(CFLAGS_BASE) $(foreach arch,$(ARCHS),-arch $(arch)) -o $@ $< -L. -ldarwinfuse

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
	rm -rf build/
	rm -f $(STATIC_LIB) $(DYLIB) $(DYLIB_LINK) $(EXAMPLES)
