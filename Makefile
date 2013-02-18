# defining the kernel to use
KERNEL_MAJOR := 3
KERNEL_MINOR := 1
KERNEL_PATCH := 10
KERNEL_HASH  := 9f22161de3c6992aa90acab0565460f565708b3a22b24205af3a31cb0f5c97ed

KERNEL_MIRROR := http://www.kernel.org/pub/

KERNEL_SHORTVER := $(KERNEL_MAJOR).$(KERNEL_MINOR)
KERNEL_VER      := $(KERNEL_SHORTVER).$(KERNEL_PATCH)
KERNEL_TARBALL  := linux-$(KERNEL_VER).tar.bz2
KERNEL_URL_PATH := linux/kernel/v$(KERNEL_SHORTVER:3.%=3.x)/$(KERNEL_TARBALL)
KERNEL_URL      := $(KERNEL_MIRROR)/$(KERNEL_URL_PATH)
KERNEL_DIR      := ./linux-$(KERNEL_VER)

# space monkey kernel revision
KERNEL_SM_REV  := 1
KERNEL_SM_PKG  := $(KERNEL_VER)-$(KERNEL_SM_REV)-armel

SHA256=shasum -a 256

DEB_ARCH := armel
DEB_PACKAGING_FILES := $(patsubst kernel-debian/%,$(KERNEL_DIR)/debian/%, \
                         $(wildcard kernel-debian/*))
DEB_VERSION := $(shell dpkg-parsechangelog -n1 -lkernel-debian/changelog \
                 | awk '$$1=="Version:" {print $$2}')
DEB_CHANGESFILE := spacemonkey-base-image_$(DEB_VERSION)_armel.changes
DEB_KERNELPKG := spacemonkey-kernel-$(KERNEL_SM_PKG)_$(DEB_VERSION)_armel.deb

HOST_ARCH := $(shell uname -m)

# Do not allow parallel execution for this top-level Makefile
.NOTPARALLEL:

CXXFLAGS := -march=armv5te
export CXXFLAGS
ARCH := arm
export ARCH

TARGET_TRIPLE=arm-linux-gnueabi
BUILDPACKAGE_ARGS = -rfakeroot -us -uc

ifeq ($(filter arm%,$(HOST_ARCH)),)
    CROSS_COMPILE = $(TARGET_TRIPLE)-
    export CROSS_COMPILE
    BUILDPACKAGE_ARGS += -t$(TARGET_TRIPLE) -d
    CC := $(TARGET_TRIPLE)-gcc
    export CC
endif

STAMPS :=
PHONY := debs

debs: $(DEB_CHANGESFILE)

PHONY += clean
clean:
	@echo "Cleaning kernel source directory"
	$(MAKE) -C $(KERNEL_DIR) clean

PHONY += cleanall
cleanall:
	@echo "Erasing kernel source directory, downloads, and stamps"
	$(RM) $(KERNEL_DIR)
	$(RM) $(KERNEL_TARBALL)
	$(RM) $(STAMPS)

$(KERNEL_DIR)/debian/%: kernel-debian/% kernel-source-stamp
	sed -e 's/#PKGVER#/$(KERNEL_SM_PKG)/g' \
	    -e 's/#SHORTVER#/$(KERNEL_SHORTVER)/g' "$<" > "$@"

$(KERNEL_TARBALL):
	@echo "Downloading linux kernel ..."
	wget "$(KERNEL_URL)" -N
	@echo "Kernel downloaded."

STAMPS += kernel-verified-stamp
kernel-verified-stamp: $(KERNEL_TARBALL)
	@echo "Verifying kernel checksum ..."
	test "$(KERNEL_HASH)" = `$(SHA256) "$<" | awk '{print $$1}'`
	touch $@

PHONY += download_kernel
download_kernel: kernel-verified-stamp

STAMPS += kernel-source-stamp
kernel-source-stamp: kernel-verified-stamp
	$(RM) -r $(KERNEL_DIR)
	@echo "Extracting kernel ..."
	tar xjf "$(KERNEL_TARBALL)"
	@echo "Patching kernel"
	patch -d $(KERNEL_DIR) -p1 < config/archlinuxarm.patch
	patch -d $(KERNEL_DIR) -p1 < config/spacemonkey.patch
	patch -d $(KERNEL_DIR) -p1 < config/fan5646.patch
	mkdir $(KERNEL_DIR)/debian
	@echo "Installing kernel configuration file"
	cp config/linux-3.1.10.config "$(KERNEL_DIR)/.config"
	touch $@

PHONY += unpack_kernel
unpack_kernel: kernel-source-stamp

$(DEB_CHANGESFILE) $(DEB_KERNELPKG): kernel-source-stamp $(DEB_PACKAGING_FILES)
	chmod 755 $(KERNEL_DIR)/debian/rules
	cd $(KERNEL_DIR) && dpkg-buildpackage $(BUILDPACKAGE_ARGS)

PHONY += kernel
kernel: $(DEB_CHANGESFILE)

BUILD_TAG_NAME=debian/spacemonkey-base-image/$(DEB_VERSION)

PHONY += upload_packages
upload_packages: $(DEB_CHANGESFILE)
	@echo "Checking for uncommitted changes..."
	[ -z "$$(git status --porcelain -uno)" ]
	@echo "Tagging build..."
	git tag $(BUILD_TAG_NAME)
	@echo "Uploading built packages to apt server..."
	SPACE_LEVEL=unstable upload-new-debs $(DEB_CHANGESFILE) \
	    apt.spacemonkey.com $(shell git config spacemonkey.user)
	@echo "Pushing tag to git server..."
	git push origin refs/tags/$(BUILD_TAG_NAME)

PHONY += usage
usage:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available targets:"
	@echo "  clean           -- clean (not erase) kernel source directory"
	@echo "  cleanall        -- remove all downloads, builds, kernel source"
	@echo "  download_kernel -- download and verify kernel source"
	@echo "  unpack_kernel   -- download, unpack, patch kernel source"
	@echo "  debs            -- build and create kernel/headers debs"
	@echo "  upload_packages -- tag build in git and upload packages to apt"

.PHONY: $(PHONY)
