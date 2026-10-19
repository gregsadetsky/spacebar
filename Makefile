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

.PHONY: all build kit cli icon test samples samples-huge install uninstall smoke release clean

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
	cp App/icon/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --sign - --entitlements Extension/Extension.entitlements --timestamp=none $(APPEX)
	codesign --force --sign - --entitlements App/App.entitlements --timestamp=none $(APP)
	codesign --verify --deep --strict $(APP)
	@echo "built $(APP)"

# --- the rest -----------------------------------------------------------------
icon:
	swiftc -O scripts/make-icon.swift -o $(BUILD)/make-icon && $(BUILD)/make-icon App/icon/AppIcon.icns

# real XCTest needs xcode. if Xcode.app exists we point at it with DEVELOPER_DIR
# (no sudo xcode-select needed). with command line tools only, the same test
# files run through a tiny XCTest look-alike (Packages/SpacebarKit/Tests/XCTestShim)
# in a separate build dir so the two never mix modules.
XCODE_DIR ?= $(firstword $(wildcard /Applications/Xcode*.app))
test:
	@if [ -n "$(XCODE_DIR)" ]; then \
		echo "xcode at $(XCODE_DIR): real XCTest"; \
		cd Packages/SpacebarKit && DEVELOPER_DIR="$(XCODE_DIR)/Contents/Developer" swift test --scratch-path .build-xctest 2>&1 | grep -E "error|Executed|failed|passed" | tail -5; \
		test $${PIPESTATUS[0]} -eq 0; \
	else \
		echo "no xcode: running tests through the XCTest shim"; \
		cd Packages/SpacebarKit && SPACEBAR_XCTEST_SHIM=1 swift run --scratch-path .build-shim spacebar-tests; \
	fi
	scripts/validate-plugins.sh

# spacebar-cli dump/match: used by make samples (harness payload) and smoke
cli:
	cd Packages/SpacebarKit && swift build --product spacebar-cli 2>&1 | grep -E "error|warning: unre" || true
	@test -x Packages/SpacebarKit/.build/debug/spacebar-cli || { echo "spacebar-cli did not build"; exit 1; }

samples: cli
	samples/make_samples.sh

samples-huge:
	HUGE=1 samples/make_samples.sh

install: build
	INSTALL_DIR="$(INSTALL_DIR)" scripts/install.sh $(APP)

# full uninstall: app, extension registration, the container with plugins + settings
uninstall:
	-pkill -x $(APP_NAME)
	-pluginkit -r "$(INSTALL_DIR)/$(APP_NAME).app/Contents/PlugIns/$(EXT_NAME).appex" 2>/dev/null
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app" "/Applications/$(APP_NAME).app"
	rm -rf "$(HOME)/Library/Containers/$(EXT_ID)" "$(HOME)/Library/Containers/$(APP_ID)"
	-qlmanage -r >/dev/null 2>&1
	@echo "uninstalled"

smoke:
	scripts/smoke.sh

release:
	VERSION=$(VERSION) scripts/release.sh

clean:
	rm -rf $(BUILD) dist Packages/SpacebarKit/.build Packages/SpacebarKit/.build-shim Packages/SpacebarKit/.build-xctest
