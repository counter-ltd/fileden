APP_NAME       := FileDen
BUNDLE_ID      := ltd.anti.FileDen
CONFIG         := release
BUILD_DIR      := build
APP_BUNDLE     := $(BUILD_DIR)/$(APP_NAME).app
EXEC_NAME      := $(APP_NAME)
INFO_PLIST     := Resources/Info.plist
ENTITLEMENTS   := Resources/FileDen.entitlements
ICONSET        := $(BUILD_DIR)/AppIcon.iconset
ICNS           := Resources/AppIcon.icns

SWIFT          := swift
CODESIGN       := codesign

BIN_PATH       = $(shell $(SWIFT) build -c $(CONFIG) --show-bin-path)

.PHONY: all build bundle run debug stop test clean format help icon

all: build

help:
	@echo "Targets:"
	@echo "  make build    — swift build -c release"
	@echo "  make bundle   — assemble FileDen.app under build/"
	@echo "  make run      — bundle + relaunch app"
	@echo "  make debug    — debug build + run in foreground"
	@echo "  make stop     — kill running FileDen"
	@echo "  make test     — swift test"
	@echo "  make clean    — swift package clean + remove build/"
	@echo "  make icon     — render AppIcon.icns from AppIconRenderer"

build:
	$(SWIFT) build -c $(CONFIG) --product $(APP_NAME)

icon: build
	@rm -rf "$(ICONSET)"
	@"$(BIN_PATH)/$(APP_NAME)" --icon "$(ICONSET)"
	@if command -v pngquant >/dev/null 2>&1; then \
		echo "Quantizing icon PNGs..."; \
		for f in $(ICONSET)/*.png; do \
			pngquant --quality=65-90 --speed 1 --force --output "$$f" "$$f"; \
		done; \
	else \
		echo "pngquant not found, skipping (brew install pngquant)"; \
	fi
	@if command -v optipng >/dev/null 2>&1; then \
		echo "Optimizing icon PNGs..."; \
		optipng -quiet -o2 $(ICONSET)/*.png; \
	else \
		echo "optipng not found, skipping (brew install optipng)"; \
	fi
	@iconutil -c icns "$(ICONSET)" -o "$(ICNS)"
	@echo "→ $(ICNS)"

bundle: build
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(BIN_PATH)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(EXEC_NAME)"
	@cp "$(INFO_PLIST)" "$(APP_BUNDLE)/Contents/Info.plist"
	@if [ -f "$(ICNS)" ]; then cp "$(ICNS)" "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"; fi
	@$(CODESIGN) --force --deep --sign - \
		--entitlements "$(ENTITLEMENTS)" \
		"$(APP_BUNDLE)"
	@echo "→ $(APP_BUNDLE)"

run: stop bundle
	@open "$(APP_BUNDLE)"
	@echo "→ launched $(APP_NAME)"

debug:
	$(SWIFT) build -c debug --product $(APP_NAME)
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(shell $(SWIFT) build -c debug --show-bin-path)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(EXEC_NAME)"
	@cp "$(INFO_PLIST)" "$(APP_BUNDLE)/Contents/Info.plist"
	@if [ -f "$(ICNS)" ]; then cp "$(ICNS)" "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"; fi
	@$(CODESIGN) --force --deep --sign - --entitlements "$(ENTITLEMENTS)" "$(APP_BUNDLE)"
	@$(MAKE) stop
	@"$(APP_BUNDLE)/Contents/MacOS/$(EXEC_NAME)"

stop:
	@pkill -x $(EXEC_NAME) 2>/dev/null || true

test:
	$(SWIFT) test

reset:
	@rm -rf "$$HOME/Library/Application Support/FileDen"
	@echo "→ wiped ~/Library/Application Support/FileDen"

clean:
	$(SWIFT) package clean
	@rm -rf "$(BUILD_DIR)"

format:
	@which swift-format >/dev/null 2>&1 && swift-format -i -r Sources Tests || echo "swift-format not installed (brew install swift-format)"
