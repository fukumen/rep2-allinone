BASE_VERSION = 1.0.3
PHP_VERSION_DEFAULT = 8.5.3
PHP_VERSION_WINDOWS = 8.5.1

CADDY_VERSION = 2.9.1
COMPOSER_VERSION = 2.9.4

REP2_REPO = https://github.com/fukumen/p2-php.git
REP2_BRANCH = php8-merge-mbstring

ARCH ?= amd64
OS ?= linux

ifeq ($(OS),windows)
PHP_VERSION = $(PHP_VERSION_WINDOWS)
PHP_URL = https://windows.php.net/downloads/releases
else
PHP_VERSION = $(PHP_VERSION_DEFAULT)
PHP_URL = https://dl.static-php.dev/static-php-cli/common
endif

COMMIT_DATE = $(shell cat dist/build_info_rep2_date 2>/dev/null || echo "unknown")
DEB_VERSION = $(BASE_VERSION)-php$(PHP_VERSION)-caddy$(CADDY_VERSION)+$(COMMIT_DATE)
RPM_VERSION = $(BASE_VERSION)
RPM_RELEASE = php$(PHP_VERSION).caddy$(CADDY_VERSION).$(COMMIT_DATE)

RUN_ID ?= local
RUN_NUMBER ?= local
REPO_TYPE = rep2-allinone

PKG_NAME = rep2-allinone
DEB_DIR = dist/$(PKG_NAME)_$(DEB_VERSION)_$(ARCH)
CONF_DEFAULT_DIR ?= /etc/default

CADDY_URL = https://github.com/caddyserver/caddy/releases/download
CACERT_URL = https://curl.se/ca/cacert.pem

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
else
PHP_FPM_EXT = tar.gz
PHP_CLI_EXT = tar.gz
CADDY_EXT = tar.gz
endif

ifeq ($(OS),windows)
PHP_CLI_FILE = php-$(PHP_VERSION)-nts-Win32-vs17-x64.$(PHP_CLI_EXT)
else
PHP_FPM_FILE = php-$(PHP_VERSION)-fpm-$(PHP_OS)-$(PHP_ARCH).$(PHP_FPM_EXT)
PHP_CLI_FILE = php-$(PHP_VERSION)-cli-$(PHP_OS)-$(PHP_ARCH).$(PHP_CLI_EXT)
endif

ifneq ($(OS),windows)
PHP_FPM_TGZ = $(DOWNLOADS_DIR)/$(PHP_FPM_FILE)
endif
PHP_CLI_TGZ = $(DOWNLOADS_DIR)/$(PHP_CLI_FILE)

ifeq ($(OS),macos)
CADDY_TGZ   = $(DOWNLOADS_DIR)/caddy_$(CADDY_VERSION)_mac_$(CADDY_ARCH).$(CADDY_EXT)
else ifeq ($(OS),windows)
CADDY_TGZ   = $(DOWNLOADS_DIR)/caddy_$(CADDY_VERSION)_windows_$(CADDY_ARCH).$(CADDY_EXT)
else
CADDY_TGZ   = $(DOWNLOADS_DIR)/caddy_$(CADDY_VERSION)_linux_$(CADDY_ARCH).$(CADDY_EXT)
endif

CACERT_PEM = $(DOWNLOADS_DIR)/cacert.pem

RPM_DIR = dist/rpmbuild

PHP_CHECKSUMS = dist/php-checksums.txt

.PHONY: all build install deb rpm macos build-macos windows build-windows clean dist-clean update-php-checksums

$(PHP_CHECKSUMS):
	$(MAKE) update-php-checksums

update-php-checksums:
	@echo "Updating $(PHP_CHECKSUMS)..."
	@mkdir -p dist
	@> $(PHP_CHECKSUMS).tmp
	@for os in linux macos windows; do \
		if [ "$$os" = "windows" ]; then \
			ver="$(PHP_VERSION_WINDOWS)"; \
			url_base="https://windows.php.net/downloads/releases"; \
			files="php-$$ver-nts-Win32-vs17-x64.zip"; \
		else \
			ver="$(PHP_VERSION_DEFAULT)"; \
			url_base="https://dl.static-php.dev/static-php-cli/common"; \
			if [ "$$os" = "macos" ]; then os_name="macos"; else os_name="linux"; fi; \
			files=""; \
			for arch in x86_64 aarch64; do \
				files="$$files php-$$ver-cli-$$os_name-$$arch.tar.gz php-$$ver-fpm-$$os_name-$$arch.tar.gz"; \
			done; \
		fi; \
		for file in $$files; do \
			url="$$url_base/$$file"; \
			if curl -sIL "$$url" | grep -q "HTTP/.* 200"; then \
				echo "Fetching checksum for $$file from $$url..."; \
				hash=$$(curl -sL "$$url" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $$1}'); \
				echo "$$hash  $$file" >> $(PHP_CHECKSUMS).tmp; \
			else \
				echo "Skipping $$file (Not Found at $$url)"; \
			fi; \
		done; \
	done
	@mv $(PHP_CHECKSUMS).tmp $(PHP_CHECKSUMS)
	@echo "$(PHP_CHECKSUMS) updated successfully."

WINDOWS_DIR = dist/windows
MACOS_DIR = dist/macos

all: build

build: dist/p2-php $(BIN_DIR)/php-fpm $(BIN_DIR)/php $(BIN_DIR)/caddy dist/build_info

dist/build_info: dist/p2-php
	@mkdir -p dist
	@echo "VER_REPO_TYPE=$(REPO_TYPE)" > $@
	@echo "VER_REPO_HASH=$(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)" >> $@
	@echo "VER_REPO_LOG=$(shell TZ=Asia/Tokyo git log -1 --format='%cd %s' --date=format-local:'%Y-%m-%d %H:%M' 2>/dev/null | base64 -w 0 || echo unknown)" >> $@
	@echo "VER_REP2_HASH=$(shell cat dist/build_info_rep2_hash 2>/dev/null || echo unknown)" >> $@
	@echo "VER_REP2_LOG=$(shell cat dist/build_info_rep2_log 2>/dev/null || echo unknown)" >> $@
	@echo "VER_RUN_ID=$(RUN_ID)" >> $@
	@echo "VER_RUN_NUMBER=$(RUN_NUMBER)" >> $@

ifneq ($(OS),windows)
$(PHP_FPM_TGZ): $(PHP_CHECKSUMS)
	mkdir -p $(DOWNLOADS_DIR)
	curl -fL -o $@.tmp "$(PHP_URL)/$(PHP_FPM_FILE)"
	@HASH=$$(grep "$(notdir $@)" $(PHP_CHECKSUMS) | awk '{print $$1}'); \
	if [ -z "$$HASH" ]; then echo "Error: Checksum not found for $(notdir $@)" >&2; exit 1; fi; \
	echo "$$HASH  $@.tmp" | (sha256sum -c || shasum -a 256 -c)
	mv $@.tmp $@
endif

$(PHP_CLI_TGZ): $(PHP_CHECKSUMS)
	mkdir -p $(DOWNLOADS_DIR)
	curl -fL -o $@.tmp "$(PHP_URL)/$(PHP_CLI_FILE)"
	@HASH=$$(grep "$(notdir $@)" $(PHP_CHECKSUMS) | awk '{print $$1}'); \
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

$(CACERT_PEM):
	mkdir -p $(DOWNLOADS_DIR)
	curl -fL -o $@ $(CACERT_URL)

ifeq ($(OS),windows)
$(BIN_DIR)/php-fpm: $(PHP_CLI_TGZ)
	mkdir -p $(BIN_DIR)
	unzip -q -o $< php-cgi.exe -d $(BIN_DIR)
	touch $@

$(BIN_DIR)/php: $(PHP_CLI_TGZ)
	mkdir -p $(BIN_DIR)
	unzip -q -o $< php.exe "*.dll" -d $(BIN_DIR)
	unzip -q -o $< "ext/*" -d $(BIN_DIR)
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
	cd dist/p2-php && git rev-parse --short HEAD > ../build_info_rep2_hash
	cd dist/p2-php && TZ=Asia/Tokyo git log -1 --format='%cd %s' --date=format-local:'%Y-%m-%d %H:%M' 2>/dev/null | base64 -w 0 > ../build_info_rep2_log
	cd dist/p2-php && TZ=Asia/Tokyo git log -1 --format="%cd" --date=format-local:"%Y%m%d%H%M" > ../build_info_rep2_date
	cd dist/p2-php && rm -rf `find . -name '.git*' -o -name 'composer.*'`

	cd dist/p2-php && patch --no-backup-if-mismatch -p1 < ../../patches/p2-php.patch
ifeq ($(OS),windows)
	cd dist/p2-php && patch --no-backup-if-mismatch -p1 < ../../patches/p2-php-windows.patch
endif

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

	sed "s|@CONF_DEFAULT_FILE@|$(CONF_DEFAULT_DIR)/$(PKG_NAME)|g" linux/rep2-allinone.service > $(DESTDIR)/etc/systemd/system/$(PKG_NAME).service
	chmod 644 $(DESTDIR)/etc/systemd/system/$(PKG_NAME).service

	mkdir -p $(DESTDIR)$(CONF_DEFAULT_DIR)
	install -m 644 linux/default $(DESTDIR)$(CONF_DEFAULT_DIR)/$(PKG_NAME)

	install -m 640 conf/Caddyfile $(DESTDIR)/etc/$(PKG_NAME)/Caddyfile
	install -m 640 conf/php-fpm.conf $(DESTDIR)/etc/$(PKG_NAME)/php-fpm.conf
	install -m 644 dist/build_info $(DESTDIR)/etc/$(PKG_NAME)/build_info

deb: build
	rm -rf $(DEB_DIR)
	make install DESTDIR=$(DEB_DIR)
	
	mkdir -p $(DEB_DIR)/DEBIAN
	cp linux/debian/control $(DEB_DIR)/DEBIAN/control
	cp linux/debian/postinst $(DEB_DIR)/DEBIAN/postinst
	cp linux/debian/prerm $(DEB_DIR)/DEBIAN/prerm
	chmod 755 $(DEB_DIR)/DEBIAN/postinst $(DEB_DIR)/DEBIAN/prerm

	echo "/etc/$(PKG_NAME)/Caddyfile" > $(DEB_DIR)/DEBIAN/conffiles
	echo "/etc/$(PKG_NAME)/php-fpm.conf" >> $(DEB_DIR)/DEBIAN/conffiles
	echo "$(CONF_DEFAULT_DIR)/$(PKG_NAME)" >> $(DEB_DIR)/DEBIAN/conffiles

	SIZE=$(du -sk $(DEB_DIR) | cut -f1); \
	sed -i "s/^Version:.*/Version: $(DEB_VERSION)/" $(DEB_DIR)/DEBIAN/control; \
	sed -i "s/^Architecture:.*/Architecture: $(ARCH)/" $(DEB_DIR)/DEBIAN/control; \
	sed -i "s/^Description:/Installed-Size: $$SIZE\nDescription:/" $(DEB_DIR)/DEBIAN/control
	
	dpkg-deb -Zxz --root-owner-group --build $(DEB_DIR)

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
		--define "_binary_payload w9.xzdio" \
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
	cp dist/build_info $(MACOS_DIR)_$(ARCH)/.rep2-allinone/conf/build_info

	cp macos/install.sh $(MACOS_DIR)_$(ARCH)/install.sh
	cp macos/uninstall.sh $(MACOS_DIR)_$(ARCH)/uninstall.sh
	cp macos/com.github.fukumen.rep2-allinone.plist.template $(MACOS_DIR)_$(ARCH)/com.github.fukumen.rep2-allinone.plist.template
	chmod +x $(MACOS_DIR)_$(ARCH)/*.sh

	cd $(MACOS_DIR)_$(ARCH) && tar czf ../$(PKG_NAME)-$(DEB_VERSION)-macos-$(ARCH).tar.gz .
	@echo "macOS $(ARCH) build completed: dist/$(PKG_NAME)-$(DEB_VERSION)-macos-$(ARCH).tar.gz"

clean:
	rm -rf dist/

dist-clean: clean
	rm -rf $(DOWNLOADS_DIR)/


windows:
	$(MAKE) OS=windows ARCH=amd64 build-windows

build-windows: build $(CACERT_PEM)
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
	install -m 644 windows/rep2-allinone.ps1 $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/rep2-allinone.ps1
	install -m 640 windows/php.ini $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/conf/php.ini
	install -m 640 windows/Caddyfile $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/conf/Caddyfile
	install -m 644 $(CACERT_PEM) $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/conf/cacert.pem
	cp dist/build_info $(WINDOWS_DIR)_$(ARCH)/rep2-allinone/conf/build_info

	cd $(WINDOWS_DIR)_$(ARCH) && zip -r ../$(PKG_NAME)-$(DEB_VERSION)-windows-$(ARCH).zip rep2-allinone
	@echo "Windows $(ARCH) build completed: dist/$(PKG_NAME)-$(DEB_VERSION)-windows-$(ARCH).zip"
