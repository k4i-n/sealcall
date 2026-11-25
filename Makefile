PREFIX ?= $(HOME)/.local
IDENTITY ?= sealcall code signing
BUNDLE_ID := io.github.k4i-n.sealcall
BIN := .build/release/sealcall

DEVELOPER_DIR := $(shell xcode-select -p 2>/dev/null)
CLT_FRAMEWORKS := $(DEVELOPER_DIR)/Library/Developer/Frameworks
CLT_LIB := $(DEVELOPER_DIR)/Library/Developer/usr/lib
ifeq ($(notdir $(DEVELOPER_DIR)),CommandLineTools)
TEST_FLAGS := -Xswiftc -F$(CLT_FRAMEWORKS) -Xlinker -F$(CLT_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS) -Xlinker -rpath -Xlinker $(CLT_LIB)
endif

.PHONY: build test signing-identity install uninstall clean

build:
	swift build -c release

test:
	swift test $(TEST_FLAGS)

signing-identity:
	scripts/signing-identity.sh "$(IDENTITY)"

install: build
	@security find-identity -p codesigning | grep -q '"$(IDENTITY)"' || \
		{ echo 'no "$(IDENTITY)" certificate: run make signing-identity first' >&2; exit 1; }
	cp $(BIN) $(BIN).signed
	codesign --force --sign "$(IDENTITY)" --identifier $(BUNDLE_ID) --options runtime --timestamp=none $(BIN).signed
	codesign --display --requirements - $(BIN).signed 2>&1 | grep -q 'certificate leaf' || \
		{ echo 'signature has no certificate requirement' >&2; exit 1; }
	mkdir -p $(PREFIX)/bin
	mv -f $(BIN).signed $(PREFIX)/bin/sealcall
	@echo "installed $(PREFIX)/bin/sealcall"

uninstall:
	rm -f $(PREFIX)/bin/sealcall

clean:
	swift package clean
