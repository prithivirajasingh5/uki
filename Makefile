KERNEL    ?= $(shell ls /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1)
WORK      := work
ROOTFS    := $(WORK)/rootfs
SQUASHFS  := $(WORK)/root.squashfs
INITRAMFS := $(WORK)/initramfs.cpio.gz
OUTPUT    := rescue.efi

# Packages that must be present on the build host
HOST_PKGS := debootstrap squashfs-tools systemd-ukify busybox-static

.PHONY: all deps rootfs squashfs initramfs uki run clean test

all: deps uki

# Check for required host packages and install any that are missing.
# Runs as part of `make all`; can also be invoked standalone with `sudo make deps`.
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
	bash src/build-rootfs.sh
	touch $@

squashfs: $(SQUASHFS)
$(SQUASHFS): $(ROOTFS)/.done
	bash src/build-squashfs.sh

initramfs: $(INITRAMFS)
$(INITRAMFS): $(SQUASHFS)
	bash src/build-initramfs.sh

uki: $(OUTPUT)
$(OUTPUT): $(INITRAMFS)
	KERNEL=$(KERNEL) bash src/build-uki.sh

run: $(OUTPUT)
	bash src/run-qemu.sh

clean:
	rm -rf $(WORK) $(OUTPUT)

test:
	bash tests/shellcheck.sh
	bash tests/smoke-test.sh
