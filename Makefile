PRODUCT_NAME := StockBar
EXECUTABLE_NAME := StockBar
VERSION := 0.3.0
BUILD_NUMBER := 9
BUILD_DIR := build
DIST_DIR := dist
APP_BUNDLE := $(BUILD_DIR)/StockBar.app
CONTENTS_DIR := $(APP_BUNDLE)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
EXECUTABLE := $(MACOS_DIR)/$(EXECUTABLE_NAME)
ARCH_DIR := $(BUILD_DIR)/arch
X86_64_EXECUTABLE := $(ARCH_DIR)/$(EXECUTABLE_NAME)-x86_64
ARM64_EXECUTABLE := $(ARCH_DIR)/$(EXECUTABLE_NAME)-arm64
ICON := Resources/AppIcon.icns
SOURCES := $(wildcard Sources/*.m)
DMG_ROOT := $(BUILD_DIR)/dmg-root
DMG_NAME := StockBar-$(VERSION).dmg
DMG := $(DIST_DIR)/$(DMG_NAME)

CC := clang
COMMON_CFLAGS := -fobjc-arc -fmodules -fmodules-cache-path=$(BUILD_DIR)/ModuleCache -I Sources -Wall -Wextra -Wpedantic -Wno-deprecated-declarations
X86_64_CFLAGS := $(COMMON_CFLAGS) -arch x86_64 -mmacosx-version-min=10.14
ARM64_CFLAGS := $(COMMON_CFLAGS) -arch arm64 -mmacosx-version-min=11.0
FRAMEWORKS := -framework AppKit -framework Foundation -framework CoreFoundation -framework IOKit
HARDWARE_SMOKE := $(BUILD_DIR)/TouchBarHardwareSmoke
QUOTE_SMOKE := $(BUILD_DIR)/QuoteServiceSmoke
INDEX_SMOKE := $(BUILD_DIR)/IndexQuoteSmoke

.PHONY: all app run smoke-test dmg release clean

all: app

app: $(EXECUTABLE)

$(X86_64_EXECUTABLE): $(SOURCES) Makefile
	@mkdir -p "$(ARCH_DIR)"
	$(CC) $(X86_64_CFLAGS) $(SOURCES) $(FRAMEWORKS) -o "$@"

$(ARM64_EXECUTABLE): $(SOURCES) Makefile
	@mkdir -p "$(ARCH_DIR)"
	$(CC) $(ARM64_CFLAGS) $(SOURCES) $(FRAMEWORKS) -o "$@"

$(EXECUTABLE): $(X86_64_EXECUTABLE) $(ARM64_EXECUTABLE) Resources/Info.plist $(ICON)
	@mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	lipo -create "$(X86_64_EXECUTABLE)" "$(ARM64_EXECUTABLE)" -output "$(EXECUTABLE)"
	cp Resources/Info.plist "$(CONTENTS_DIR)/Info.plist"
	cp "$(ICON)" "$(RESOURCES_DIR)/AppIcon.icns"
	@codesign --force --sign - --timestamp=none "$(APP_BUNDLE)" >/dev/null
	@echo "Built $(APP_BUNDLE)"

run: app
	open "$(APP_BUNDLE)"

$(HARDWARE_SMOKE): Tests/TouchBarHardwareSmoke.m Sources/TouchBarHardware.m
	@mkdir -p "$(BUILD_DIR)"
	$(CC) $(COMMON_CFLAGS) -mmacosx-version-min=10.14 Tests/TouchBarHardwareSmoke.m Sources/TouchBarHardware.m -framework Foundation -framework IOKit -o "$@"

$(QUOTE_SMOKE): Tests/QuoteServiceSmoke.m Sources/TencentQuoteService.m Sources/WatchlistStore.m Sources/StockQuote.m
	@mkdir -p "$(BUILD_DIR)"
	$(CC) $(COMMON_CFLAGS) -mmacosx-version-min=10.14 Tests/QuoteServiceSmoke.m Sources/TencentQuoteService.m Sources/WatchlistStore.m Sources/StockQuote.m -framework Foundation -framework CoreFoundation -o "$@"

$(INDEX_SMOKE): Tests/IndexQuoteSmoke.m Sources/TencentQuoteService.m Sources/WatchlistStore.m Sources/StockQuote.m
	@mkdir -p "$(BUILD_DIR)"
	$(CC) $(COMMON_CFLAGS) -mmacosx-version-min=10.14 Tests/IndexQuoteSmoke.m Sources/TencentQuoteService.m Sources/WatchlistStore.m Sources/StockQuote.m -framework Foundation -framework CoreFoundation -o "$@"

smoke-test: $(HARDWARE_SMOKE) $(QUOTE_SMOKE) $(INDEX_SMOKE)
	"$(HARDWARE_SMOKE)"
	"$(QUOTE_SMOKE)" auto
	"$(INDEX_SMOKE)" auto
	"$(INDEX_SMOKE)" tencent
	"$(INDEX_SMOKE)" eastmoney

$(DMG): $(EXECUTABLE)
	@mkdir -p "$(DIST_DIR)"
	rm -rf "$(DMG_ROOT)"
	@mkdir -p "$(DMG_ROOT)"
	ditto "$(APP_BUNDLE)" "$(DMG_ROOT)/$(PRODUCT_NAME).app"
	ln -s /Applications "$(DMG_ROOT)/Applications"
	hdiutil create -volname "$(PRODUCT_NAME)" -srcfolder "$(DMG_ROOT)" -ov -format UDZO "$(DMG)"

dmg: $(DMG)

release: $(DMG)
	@shasum -a 256 "$(DMG)" > "$(DIST_DIR)/SHA256SUMS"
	@echo "Release artifacts are in $(DIST_DIR)/"

clean:
	rm -rf "$(BUILD_DIR)"
