PRODUCT_NAME := StockBar
EXECUTABLE_NAME := StockBar
VERSION := 0.7.2
BUILD_NUMBER := 20
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
ICON_ARTWORK := Resources/AppIcon-artwork.png
ICON_TOOL := $(BUILD_DIR)/MakeICNS
ICONSET := $(BUILD_DIR)/AppIcon.iconset
SOURCES := $(wildcard Sources/*.m)
HEADERS := $(wildcard Sources/*.h)
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
FUND_TEST := $(BUILD_DIR)/FundSupportTest
GROUP_TEST := $(BUILD_DIR)/WatchlistGroupsTest
GROUP_TABS_TEST := $(BUILD_DIR)/GroupTabsTest
GROUP_SELECTION_TEST := $(BUILD_DIR)/GroupSelectionTest
GROUP_POPUP_TEST := $(BUILD_DIR)/GroupManagementPopupTest
SEARCH_TEST := $(BUILD_DIR)/StockSearchTest
SEARCH_SMOKE := $(BUILD_DIR)/StockSearchSmoke
SEARCH_PANEL_TEST := $(BUILD_DIR)/StockSearchPanelTest

.PHONY: all app icon run test ui-test smoke-test search-smoke dmg release clean

all: app

app: $(EXECUTABLE)

$(ICON_TOOL): Tools/MakeICNS.m
	@mkdir -p "$(BUILD_DIR)"
	$(CC) -fobjc-arc -Wall -Wextra Tools/MakeICNS.m -framework AppKit -framework Foundation -o "$@"

icon: $(ICON_TOOL) $(ICON_ARTWORK)
	"$(ICON_TOOL)" "$(ICON_ARTWORK)" "$(ICONSET)" "$(ICON)"
	cp "$(ICONSET)/icon_512x512@2x.png" Resources/AppIcon-1024.png

$(X86_64_EXECUTABLE): $(SOURCES) $(HEADERS) Makefile
	@mkdir -p "$(ARCH_DIR)"
	$(CC) $(X86_64_CFLAGS) $(SOURCES) $(FRAMEWORKS) -o "$@"

$(ARM64_EXECUTABLE): $(SOURCES) $(HEADERS) Makefile
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
	"$(QUOTE_SMOKE)" tencent
	"$(QUOTE_SMOKE)" eastmoney
	"$(INDEX_SMOKE)" auto
	"$(INDEX_SMOKE)" tencent
	"$(INDEX_SMOKE)" eastmoney

$(FUND_TEST): Tests/FundSupportTest.m Sources/WatchlistStore.m Sources/StockQuote.m $(HEADERS)
	@mkdir -p "$(BUILD_DIR)"
	$(CC) $(COMMON_CFLAGS) -mmacosx-version-min=10.14 Tests/FundSupportTest.m Sources/WatchlistStore.m Sources/StockQuote.m -framework Foundation -o "$@"

$(GROUP_TEST): Tests/WatchlistGroupsTest.m Sources/WatchlistStore.m $(HEADERS)
	@mkdir -p "$(BUILD_DIR)"
	$(CC) $(COMMON_CFLAGS) -mmacosx-version-min=10.14 Tests/WatchlistGroupsTest.m Sources/WatchlistStore.m -framework Foundation -o "$@"

$(SEARCH_TEST): Tests/StockSearchTest.m Sources/StockSearchService.m Sources/WatchlistStore.m $(HEADERS)
	@mkdir -p "$(BUILD_DIR)"
	$(CC) $(COMMON_CFLAGS) -mmacosx-version-min=10.14 Tests/StockSearchTest.m Sources/StockSearchService.m Sources/WatchlistStore.m -framework Foundation -framework CoreFoundation -o "$@"

$(SEARCH_SMOKE): Tests/StockSearchSmoke.m Sources/StockSearchService.m Sources/WatchlistStore.m $(HEADERS)
	@mkdir -p "$(BUILD_DIR)"
	$(CC) $(COMMON_CFLAGS) -mmacosx-version-min=10.14 Tests/StockSearchSmoke.m Sources/StockSearchService.m Sources/WatchlistStore.m -framework Foundation -framework CoreFoundation -o "$@"

search-smoke: $(SEARCH_SMOKE)
	"$(SEARCH_SMOKE)"

test: $(FUND_TEST) $(GROUP_TEST) $(SEARCH_TEST)
	"$(FUND_TEST)"
	"$(GROUP_TEST)"
	"$(SEARCH_TEST)"

$(GROUP_TABS_TEST): Tests/GroupTabsTest.m Sources/GroupTabsMenuItemView.m Sources/WatchlistStore.m $(HEADERS)
	@mkdir -p "$(BUILD_DIR)"
	$(CC) $(COMMON_CFLAGS) -mmacosx-version-min=10.14 Tests/GroupTabsTest.m Sources/GroupTabsMenuItemView.m Sources/WatchlistStore.m -framework AppKit -framework Foundation -o "$@"

$(GROUP_SELECTION_TEST): Tests/GroupSelectionTest.m $(filter-out Sources/main.m,$(SOURCES)) $(HEADERS)
	@mkdir -p "$(BUILD_DIR)"
	$(CC) $(COMMON_CFLAGS) -mmacosx-version-min=10.14 Tests/GroupSelectionTest.m $(filter-out Sources/main.m,$(SOURCES)) $(FRAMEWORKS) -o "$@"

$(GROUP_POPUP_TEST): Tests/GroupManagementPopupTest.m Sources/GroupTabsMenuItemView.m Sources/WatchlistStore.m $(HEADERS)
	@mkdir -p "$(BUILD_DIR)"
	$(CC) $(COMMON_CFLAGS) -mmacosx-version-min=10.14 Tests/GroupManagementPopupTest.m Sources/GroupTabsMenuItemView.m Sources/WatchlistStore.m -framework AppKit -framework Foundation -o "$@"

$(SEARCH_PANEL_TEST): Tests/StockSearchPanelTest.m Sources/AddStockMenuItemView.m Sources/StockSearchWindowController.m Sources/StockSearchService.m Sources/WatchlistStore.m $(HEADERS)
	@mkdir -p "$(BUILD_DIR)"
	$(CC) $(COMMON_CFLAGS) -mmacosx-version-min=10.14 Tests/StockSearchPanelTest.m Sources/AddStockMenuItemView.m Sources/StockSearchWindowController.m Sources/StockSearchService.m Sources/WatchlistStore.m -framework AppKit -framework Foundation -framework CoreFoundation -o "$@"

ui-test: $(GROUP_TABS_TEST) $(GROUP_SELECTION_TEST) $(GROUP_POPUP_TEST) $(SEARCH_PANEL_TEST)
	"$(GROUP_TABS_TEST)" "$(BUILD_DIR)/group-tabs.png"
	"$(GROUP_SELECTION_TEST)"
	"$(GROUP_POPUP_TEST)"
	"$(SEARCH_PANEL_TEST)" "$(BUILD_DIR)/stock-search.png"

$(DMG): $(EXECUTABLE)
	@mkdir -p "$(DIST_DIR)"
	rm -rf "$(DMG_ROOT)"
	@mkdir -p "$(DMG_ROOT)"
	ditto "$(APP_BUNDLE)" "$(DMG_ROOT)/$(PRODUCT_NAME).app"
	ln -s /Applications "$(DMG_ROOT)/Applications"
	hdiutil create -volname "$(PRODUCT_NAME)" -srcfolder "$(DMG_ROOT)" -ov -format UDZO "$(DMG)"

dmg: $(DMG)

release: $(DMG)
	@cd "$(DIST_DIR)" && shasum -a 256 "$(DMG_NAME)" > SHA256SUMS
	@echo "Release artifacts are in $(DIST_DIR)/"

clean:
	rm -rf "$(BUILD_DIR)"
