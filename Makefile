BASE_VERSION = 1.0.0
PHP_VERSION = 8.5.3
CADDY_VERSION = 2.9.1
COMPOSER_VERSION = 2.9.4

REP2_REPO = https://github.com/fukumen/p2-php.git
REP2_BRANCH = php8-merge-mbstring

COMMIT_DATE = $(shell [ -d dist/p2-php ] && cd dist/p2-php && TZ=Asia/Tokyo git log -1 --format="%cd" --date=format-local:"%Y%m%d%H%M" || echo "unknown")
DEB_VERSION = $(BASE_VERSION)-php$(PHP_VERSION)-caddy$(CADDY_VERSION)+$(COMMIT_DATE)
RPM_VERSION = $(BASE_VERSION)
RPM_RELEASE = php$(PHP_VERSION).caddy$(CADDY_VERSION).$(COMMIT_DATE)

ARCH ?= amd64
OS ?= linux
PKG_NAME = rep2-allinone
DEB_DIR = dist/$(PKG_NAME)_$(DEB_VERSION)_$(ARCH)

PHP_URL = https://dl.static-php.dev/static-php-cli/common
CADDY_URL = https://github.com/caddyserver/caddy/releases/download

ifeq ($(OS),macos)
PHP_OS = macos
CADDY_OS = mac
else ifeq ($(OS),windows)
PHP_OS = windows
CADDY_OS = windows
else
PHP_OS = linux
CADDY_OS = linux
endif

ifeq ($(ARCH),arm64)
PHP_ARCH = aarch64
CADDY_ARCH = arm64
RPM_ARCH = aarch64
else
PHP_ARCH = x86_64
CADDY_ARCH = amd64
RPM_ARCH = x86_64
endif

DOWNLOADS_DIR = downloads
BIN_DIR = dist/bin-$(OS)-$(ARCH)

ifeq ($(OS),windows)
PHP_FPM_EXT = zip
PHP_CLI_EXT = zip
CADDY_EXT = zip
PHP_FPM_PREFIX = cgi
else
PHP_FPM_EXT = tar.gz
PHP_CLI_EXT = tar.gz
CADDY_EXT = tar.gz
PHP_FPM_PREFIX = fpm
endif

PHP_FPM_TGZ = $(DOWNLOADS_DIR)/php-$(PHP_VERSION)-$(PHP_FPM_PREFIX)-$(PHP_OS)-$(PHP_ARCH).$(PHP_FPM_EXT)
PHP_CLI_TGZ = $(DOWNLOADS_DIR)/php-$(PHP_VERSION)-cli-$(PHP_OS)-$(PHP_ARCH).$(PHP_CLI_EXT)

ifeq ($(OS),macos)
CADDY_TGZ   = $(DOWNLOADS_DIR)/caddy_$(CADDY_VERSION)_mac_$(CADDY_ARCH).$(CADDY_EXT)
else ifeq ($(OS),windows)
CADDY_TGZ   = $(DOWNLOADS_DIR)/caddy_$(CADDY_VERSION)_windows_$(CADDY_ARCH).$(CADDY_EXT)
else
CADDY_TGZ   = $(DOWNLOADS_DIR)/caddy_$(CADDY_VERSION)_linux_$(CADDY_ARCH).$(CADDY_EXT)
endif

RPM_DIR = dist/rpmbuild

.PHONY: all build install deb rpm macos build-macos windows build-windows clean dist-clean update-php-checksums

update-php-checksums:
	@echo "Updating php-checksums.txt for PHP $(PHP_VERSION)..."
	@> php-checksums.tmp
	@for os in linux macos windows; do \
		for arch in x86_64 aarch64; do \
			if [ "$$os" = "windows" ]; then \
				types="cli cgi"; \
				ext="zip"; \
			else \
				types="cli fpm"; \
				ext="tar.gz"; \
			fi; \
			for type in $$types; do \
				file="php-$(PHP_VERSION)-$$type-$$os-$$arch.$$ext"; \
				url="$(PHP_URL)/$$file"; \
				if curl -sI "$$url" | head -n 1 | grep -qE "200|302"; then \
					echo "Fetching checksum for $$file..."; \
					hash=$$(curl -sL "$$url" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $$1}'); \
					echo "$$hash  $$file" >> php-checksums.tmp; \
				else \
					echo "Skipping $$file (Not Found)"; \
				fi; \
			done; \
		done; \
	done
	@mv php-checksums.tmp php-checksums.txt
	@echo "php-checksums.txt updated successfully."

WINDOWS_DIR = dist/windows
MACOS_DIR = dist/macos

all: build

build: dist/p2-php $(BIN_DIR)/php-fpm $(BIN_DIR)/php $(BIN_DIR)/caddy

$(PHP_FPM_TGZ):
	mkdir -p $(DOWNLOADS_DIR)
	curl -fL -o $@.tmp "$(PHP_URL)/php-$(PHP_VERSION)-$(PHP_FPM_PREFIX)-$(PHP_OS)-$(PHP_ARCH).$(PHP_FPM_EXT)"
	@HASH=$$(grep "$(notdir $@)" php-checksums.txt | awk '{print $$1}'); \
	if [ -z "$$HASH" ]; then echo "Error: Checksum not found for $(notdir $@)" >&2; exit 1; fi; \
	echo "$$HASH  $@.tmp" | (sha256sum -c || shasum -a 256 -c)
	mv $@.tmp $@

$(PHP_CLI_TGZ):
	mkdir -p $(DOWNLOADS_DIR)
	curl -fL -o $@.tmp "$(PHP_URL)/php-$(PHP_VERSION)-cli-$(PHP_OS)-$(PHP_ARCH).$(PHP_CLI_EXT)"
	@HASH=$$(grep "$(notdir $@)" php-checksums.txt | awk '{print $$1}'); \
	if [ -z "$$HASH" ]; then echo "Error: Checksum not found for $(notdir $@)" >&2; exit 1; fi; \
	echo "$$HASH  $@.tmp" | (sha256sum -c || shasum -a 256 -c)
	mv $@.tmp $@

$(CADDY_TGZ):
	mkdir -p $(DOWNLOADS_DIR)
	@if [ "$(OS)" = "macos" ]; then \
		curl -fL -o $@.tmp "$(CADDY_URL)/v$(CADDY_VERSION)/caddy_$(CADDY_VERSION)_mac_$(CADDY_ARCH).$(CADDY_EXT)"; \
	elif [ "$(OS)" = "windows" ]; then \
		curl -fL -o $@.tmp "$(CADDY_URL)/v$(CADDY_VERSION)/caddy_$(CADDY_VERSION)_windows_$(CADDY_ARCH).$(CADDY_EXT)"; \
	else \
		curl -fL -o $@.tmp "$(CADDY_URL)/v$(CADDY_VERSION)/caddy_$(CADDY_VERSION)_linux_$(CADDY_ARCH).$(CADDY_EXT)"; \
	fi
	curl -sL -o $(DOWNLOADS_DIR)/caddy_$(CADDY_VERSION)_checksums.txt "$(CADDY_URL)/v$(CADDY_VERSION)/caddy_$(CADDY_VERSION)_checksums.txt"
	@HASH=$$(grep "$(notdir $@)" $(DOWNLOADS_DIR)/caddy_$(CADDY_VERSION)_checksums.txt | awk '{print $$1}'); \
	if [ -z "$$HASH" ]; then echo "Error: Checksum not found for $(notdir $@)" >&2; exit 1; fi; \
	echo "$$HASH  $@.tmp" | (sha512sum -c || shasum -a 512 -c)
	mv $@.tmp $@

ifeq ($(OS),windows)
$(BIN_DIR)/php-fpm: $(PHP_FPM_TGZ)
	mkdir -p $(BIN_DIR)
	unzip -q -o $< php-cgi.exe -d $(BIN_DIR) || unzip -q -o $< -d $(BIN_DIR)
	touch $@

$(BIN_DIR)/php: $(PHP_CLI_TGZ)
	mkdir -p $(BIN_DIR)
	unzip -q -o $< php.exe -d $(BIN_DIR) || unzip -q -o $< -d $(BIN_DIR)
	touch $@

$(BIN_DIR)/caddy: $(CADDY_TGZ)
	mkdir -p $(BIN_DIR)
	unzip -q -o $< caddy.exe -d $(BIN_DIR)
	touch $@
else
$(BIN_DIR)/php-fpm: $(PHP_FPM_TGZ)
	mkdir -p $(BIN_DIR)
	tar xzf $< -C $(BIN_DIR)
	touch $@

$(BIN_DIR)/php: $(PHP_CLI_TGZ)
	mkdir -p $(BIN_DIR)
	tar xzf $< -C $(BIN_DIR)
	touch $@

$(BIN_DIR)/caddy: $(CADDY_TGZ)
	mkdir -p $(BIN_DIR)
	tar xzf $< -C $(BIN_DIR) caddy
	touch $@
endif

dist/p2-php:
	git clone --depth 1 -b $(REP2_BRANCH) $(REP2_REPO) dist/p2-php

	cd dist && curl https://getcomposer.org/installer | php -- --version $(COMPOSER_VERSION)
	cd dist/p2-php && ../composer.phar install
	cd dist/p2-php && rm -rf `find . -name '.git*' -o -name 'composer.*'`

	cd dist/p2-php && patch --no-backup-if-mismatch -p1 < ../../patches/p2-php.patch

install: build
	mkdir -p $(DESTDIR)/opt/$(PKG_NAME)/bin
	mkdir -p $(DESTDIR)/opt/$(PKG_NAME)/p2-php
	mkdir -p $(DESTDIR)/etc/$(PKG_NAME)
	mkdir -p $(DESTDIR)/etc/systemd/system

	cp -r $(BIN_DIR)/* $(DESTDIR)/opt/$(PKG_NAME)/bin/

	rsync -a --exclude="rep2/ic/" dist/p2-php/ $(DESTDIR)/opt/$(PKG_NAME)/p2-php/

	mv $(DESTDIR)/opt/$(PKG_NAME)/p2-php/conf $(DESTDIR)/opt/$(PKG_NAME)/p2-php/conf.orig
	mv $(DESTDIR)/opt/$(PKG_NAME)/p2-php/data $(DESTDIR)/opt/$(PKG_NAME)/p2-php/data.orig

	mkdir -p $(DESTDIR)/opt/$(PKG_NAME)/p2-php/rep2

	install -m 755 linux/rep2-allinone $(DESTDIR)/opt/$(PKG_NAME)/rep2-allinone

	install -m 644 linux/rep2-allinone.service $(DESTDIR)/etc/systemd/system/

	install -m 640 conf/Caddyfile $(DESTDIR)/etc/$(PKG_NAME)/Caddyfile
	install -m 640 conf/php-fpm.conf $(DESTDIR)/etc/$(PKG_NAME)/php-fpm.conf

deb: build
	rm -rf $(DEB_DIR)
	make install DESTDIR=$(DEB_DIR)
	
	mkdir -p $(DEB_DIR)/DEBIAN
	cp linux/debian/control $(DEB_DIR)/DEBIAN/control
	cp linux/debian/postinst $(DEB_DIR)/DEBIAN/postinst
	cp linux/debian/prerm $(DEB_DIR)/DEBIAN/prerm
	chmod 755 $(DEB_DIR)/DEBIAN/postinst $(DEB_DIR)/DEBIAN/prerm
	
	SIZE=$$(du -sk $(DEB_DIR) | cut -f1); \
	sed -i "s/^Version:.*/Version: $(DEB_VERSION)/" $(DEB_DIR)/DEBIAN/control; \
	sed -i "s/^Architecture:.*/Architecture: $(ARCH)/" $(DEB_DIR)/DEBIAN/control; \
	sed -i "s/^Description:/Installed-Size: $$SIZE\nDescription:/" $(DEB_DIR)/DEBIAN/control
	
	dpkg-deb --root-owner-group --build $(DEB_DIR)

rpm: build
	rm -rf $(RPM_DIR)
	mkdir -p $(RPM_DIR)/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
	rpmbuild -bb \
		--define "_topdir $$(pwd)/$(RPM_DIR)" \
		--define "_version $(RPM_VERSION)" \
		--define "_release $(RPM_RELEASE)" \
		--define "_target_cpu $(RPM_ARCH)" \
		--define "_orig_arch $(ARCH)" \
		--define "_workspace $$(pwd)" \
		linux/rpm/rep2-allinone.spec
	find $(RPM_DIR)/RPMS -name "*.rpm" -exec cp {} dist/ \;


macos:
	$(MAKE) OS=macos ARCH=arm64 build-macos
	$(MAKE) OS=macos ARCH=amd64 build-macos

build-macos: build
	rm -rf $(MACOS_DIR)_$(ARCH)
	mkdir -p $(MACOS_DIR)_$(ARCH)/.rep2-allinone/bin
	mkdir -p $(MACOS_DIR)_$(ARCH)/.rep2-allinone/conf
	mkdir -p $(MACOS_DIR)_$(ARCH)/.rep2-allinone/var
	mkdir -p $(MACOS_DIR)_$(ARCH)/.rep2-allinone/p2-php

	cp -r $(BIN_DIR)/* $(MACOS_DIR)_$(ARCH)/.rep2-allinone/bin/
	rsync -a --exclude="rep2/ic/" dist/p2-php/ $(MACOS_DIR)_$(ARCH)/.rep2-allinone/p2-php/

	mv $(MACOS_DIR)_$(ARCH)/.rep2-allinone/p2-php/conf $(MACOS_DIR)_$(ARCH)/.rep2-allinone/p2-php/conf.orig
	mv $(MACOS_DIR)_$(ARCH)/.rep2-allinone/p2-php/data $(MACOS_DIR)_$(ARCH)/.rep2-allinone/p2-php/data.orig
	mkdir -p $(MACOS_DIR)_$(ARCH)/.rep2-allinone/p2-php/rep2

	install -m 755 macos/rep2-allinone $(MACOS_DIR)_$(ARCH)/.rep2-allinone/rep2-allinone
	install -m 640 conf/php-fpm.conf $(MACOS_DIR)_$(ARCH)/.rep2-allinone/conf/php-fpm.conf
	install -m 640 macos/Caddyfile $(MACOS_DIR)_$(ARCH)/.rep2-allinone/conf/Caddyfile

	cp macos/install.sh $(MACOS_DIR)_$(ARCH)/install.sh
	cp macos/uninstall.sh $(MACOS_DIR)_$(ARCH)/uninstall.sh
	cp macos/com.github.fukumen.rep2-allinone.plist.template $(MACOS_DIR)_$(ARCH)/com.github.fukumen.rep2-allinone.plist.template
	chmod +x $(MACOS_DIR)_$(ARCH)/*.sh

	cd $(MACOS_DIR)_$(ARCH) && tar czf ../$(PKG_NAME)-macos-$(ARCH).tar.gz .
	@echo "macOS $(ARCH) build completed: dist/$(PKG_NAME)-macos-$(ARCH).tar.gz"

clean:
	rm -rf dist/

dist-clean: clean
	rm -rf $(DOWNLOADS_DIR)/


windows:
	$(MAKE) OS=windows ARCH=amd64 build-windows

build-windows: build
	rm -rf $(WINDOWS_DIR)_$(ARCH)
	mkdir -p $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/bin
	mkdir -p $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/conf
	mkdir -p $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/var
	mkdir -p $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/p2-php

	cp -r $(BIN_DIR)/* $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/bin/
	rsync -a --exclude="rep2/ic/" dist/p2-php/ $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/p2-php/

	mv $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/p2-php/conf $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/p2-php/conf.orig
	mv $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/p2-php/data $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/p2-php/data.orig
	mkdir -p $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/p2-php/rep2

	install -m 755 windows/rep2-allinone.bat $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/rep2-allinone.bat
	install -m 640 windows/php.ini $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/conf/php.ini
	install -m 640 windows/Caddyfile $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/conf/Caddyfile

	cd $(WINDOWS_DIR)_$(ARCH) && zip -r ../$(PKG_NAME)-windows-$(ARCH).zip rep2-allinone
	@echo "Windows $(ARCH) build completed: dist/$(PKG_NAME)-windows-$(ARCH).zip"
