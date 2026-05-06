VARIANT   ?= full
KERNEL    ?= $(shell ls /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1)
WORK      := work/$(VARIANT)
ROOTFS    := $(WORK)/rootfs
SQUASHFS  := $(WORK)/root.squashfs
IDIR      := $(WORK)/initramfs-stage
INITRAMFS := $(WORK)/initramfs.cpio.gz
OUTPUT    := rescue-$(VARIANT).efi

# Packages that must be present on the build host
HOST_PKGS := debootstrap squashfs-tools systemd-ukify busybox-static

.PHONY: all deps full mini rootfs squashfs initramfs uki run clean test

all: deps uki

full:
	$(MAKE) VARIANT=full

mini:
	$(MAKE) VARIANT=mini

# Check for required host packages and install any that are missing.
deps:
	@missing=""; \
	for pkg in $(HOST_PKGS); do \
	    dpkg -s "$$pkg" >/dev/null 2>&1 || missing="$$missing $$pkg"; \
	done; \
	if [ -n "$$missing" ]; then \
	    echo "==> Installing missing build dependencies:$$missing"; \
	    apt-get update -qq && apt-get install -y $$missing; \
	else \
	    echo "==> All build dependencies satisfied."; \
	fi

rootfs: $(ROOTFS)/.done
$(ROOTFS)/.done:
	ROOTFS=$(ROOTFS) VARIANT=$(VARIANT) bash src/build-rootfs.sh
	touch $@

squashfs: $(SQUASHFS)
$(SQUASHFS): $(ROOTFS)/.done
	ROOTFS=$(ROOTFS) SQUASHFS=$(SQUASHFS) bash src/build-squashfs.sh

initramfs: $(INITRAMFS)
$(INITRAMFS): $(SQUASHFS)
	SQUASHFS=$(SQUASHFS) IDIR=$(IDIR) INITRAMFS=$(INITRAMFS) bash src/build-initramfs.sh

uki: $(OUTPUT)
$(OUTPUT): $(INITRAMFS)
	KERNEL=$(KERNEL) INITRAMFS=$(INITRAMFS) OUTPUT=$(OUTPUT) bash src/build-uki.sh

run: $(OUTPUT)
	OUTPUT=$(OUTPUT) EFI_IMG=$(WORK)/efi.img bash src/run-qemu.sh

clean:
	rm -rf work rescue-full.efi rescue-mini.efi

test:
	bash tests/shellcheck.sh
	bash tests/smoke-test.sh
