# spacebar: plugin-based quick look host. built with swiftc only (no xcode needed).
#
#   make build     -> build/Spacebar.app (debug, ad-hoc signed)
#   make test      -> swift test in Packages/SpacebarKit + plugin validation
#   make samples   -> generate samples/
#   make install   -> copy to ~/Applications, register + enable the extension
#   make smoke     -> scripts/smoke.sh against samples/
#   make release   -> dist/Spacebar-<version>.zip + sha256
#   make clean

VERSION      ?= 0.1.0
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
CONFIG       ?= debug
ARCH         ?= $(shell uname -m)
MIN_OS       ?= 14.0
TARGET       := $(ARCH)-apple-macos$(MIN_OS)
SDK          := $(shell xcrun --show-sdk-path)
INSTALL_DIR  ?= $(HOME)/Applications

APP_ID       := io.spacebar.app
EXT_ID       := io.spacebar.app.QuickLook
APP_NAME     := Spacebar
EXT_NAME     := SpacebarQuickLook

BUILD        := build
APP          := $(BUILD)/$(APP_NAME).app
APPEX        := $(APP)/Contents/PlugIns/$(EXT_NAME).appex
KIT_DIR      := $(BUILD)/kit
KIT_LIB      := $(KIT_DIR)/libSpacebarKit.a

KIT_SRC      := $(shell find Packages/SpacebarKit/Sources/SpacebarKit -name '*.swift')
EXT_SRC      := $(shell find Extension -name '*.swift')
APP_SRC      := $(shell find App -name '*.swift') Extension/PreviewWebView.swift
PLUGIN_FILES := $(shell find plugins -type f 2>/dev/null)

ifeq ($(CONFIG),release)
OPT := -O -whole-module-optimization
else
OPT := -Onone -g -DDEBUG
endif

SWIFTC := swiftc -sdk $(SDK) -target $(TARGET) $(OPT) -parse-as-library -swift-version 5

.PHONY: all build kit test samples samples-huge install uninstall smoke release clean gen

all: build

# --- SpacebarKit as a static library both executables link against -----------
$(KIT_LIB): $(KIT_SRC)
	@mkdir -p $(KIT_DIR)
	$(SWIFTC) -module-name SpacebarKit -emit-library -static -emit-module \
		-emit-module-path $(KIT_DIR)/SpacebarKit.swiftmodule \
		$(KIT_SRC) -o $(KIT_LIB)

kit: $(KIT_LIB)

# --- extension --------------------------------------------------------------
$(APPEX)/Contents/MacOS/$(EXT_NAME): $(EXT_SRC) $(KIT_LIB) Extension/Info.plist Extension/Extension.entitlements
	@mkdir -p $(APPEX)/Contents/MacOS $(APPEX)/Contents/Resources
	$(SWIFTC) -module-name $(EXT_NAME) -application-extension \
		-I $(KIT_DIR) -L $(KIT_DIR) -lSpacebarKit \
		-framework AppKit -framework QuickLookUI -framework WebKit -lsqlite3 \
		-Xlinker -e -Xlinker _NSExtensionMain \
		$(EXT_SRC) -o $@
	sed -e 's/__VERSION__/$(VERSION)/' -e 's/__BUILD__/$(BUILD_NUMBER)/' Extension/Info.plist > $(APPEX)/Contents/Info.plist
	printf 'XPC!????' > $(APPEX)/Contents/PkgInfo

# --- app ----------------------------------------------------------------------
$(APP)/Contents/MacOS/$(APP_NAME): $(APP_SRC) $(KIT_LIB) App/Info.plist App/App.entitlements
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	$(SWIFTC) -module-name $(APP_NAME) \
		-I $(KIT_DIR) -L $(KIT_DIR) -lSpacebarKit \
		-framework AppKit -framework SwiftUI -framework WebKit -lsqlite3 \
		$(APP_SRC) -o $@
	sed -e 's/__VERSION__/$(VERSION)/' -e 's/__BUILD__/$(BUILD_NUMBER)/' App/Info.plist > $(APP)/Contents/Info.plist
	printf 'APPL????' > $(APP)/Contents/PkgInfo

# --- bundle assembly + signing -----------------------------------------------
build: $(APPEX)/Contents/MacOS/$(EXT_NAME) $(APP)/Contents/MacOS/$(APP_NAME) $(PLUGIN_FILES)
	rm -rf $(APP)/Contents/Resources/Plugins
	@if [ -d plugins ]; then cp -R plugins $(APP)/Contents/Resources/Plugins; fi
	codesign --force --sign - --entitlements Extension/Extension.entitlements --timestamp=none $(APPEX)
	codesign --force --sign - --entitlements App/App.entitlements --timestamp=none $(APP)
	codesign --verify --deep --strict $(APP)
	@echo "built $(APP)"

# --- the rest -----------------------------------------------------------------
# real XCTest needs xcode; with command line tools only, the same test files
# run through a tiny XCTest look-alike (Packages/SpacebarKit/Tests/XCTestShim)
test:
	@if xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then \
		cd Packages/SpacebarKit && swift test; \
	else \
		echo "no xcode: running tests through the XCTest shim"; \
		cd Packages/SpacebarKit && SPACEBAR_XCTEST_SHIM=1 swift run spacebar-tests; \
	fi
	scripts/validate-plugins.sh

samples:
	samples/make_samples.sh

samples-huge:
	HUGE=1 samples/make_samples.sh

install: build
	INSTALL_DIR="$(INSTALL_DIR)" scripts/install.sh $(APP)

uninstall:
	pluginkit -r "$(INSTALL_DIR)/$(APP_NAME).app/Contents/PlugIns/$(EXT_NAME).appex" 2>/dev/null || true
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	qlmanage -r >/dev/null 2>&1 || true

smoke:
	scripts/smoke.sh

release:
	VERSION=$(VERSION) scripts/release.sh

clean:
	rm -rf $(BUILD) dist Packages/SpacebarKit/.build
