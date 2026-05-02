KERNEL    ?= $(shell ls /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1)
WORK      := work
ROOTFS    := $(WORK)/rootfs
SQUASHFS  := $(WORK)/root.squashfs
INITRAMFS := $(WORK)/initramfs.cpio.gz
OUTPUT    := rescue.efi

.PHONY: all rootfs squashfs initramfs uki run clean test

all: uki

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
