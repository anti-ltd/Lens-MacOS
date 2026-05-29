APP_NAME       := Lens
BUNDLE_ID      := ltd.anti.lens
CONFIG         := release
BUILD_DIR      := build
APP_BUNDLE     := $(BUILD_DIR)/$(APP_NAME).app
DMG            := $(BUILD_DIR)/$(APP_NAME).dmg
EXEC_NAME      := $(APP_NAME)
INFO_PLIST     := Resources/Info.plist
ENTITLEMENTS   := Resources/Lens.entitlements
ICONSET        := $(BUILD_DIR)/AppIcon.iconset
ICNS           := Resources/AppIcon.icns

SWIFT          := swift
CODESIGN       := codesign
STRIP          := strip

# Stable signing identity so macOS keeps the Screen Recording / Accessibility
# (TCC) grant across rebuilds — without it every rebuild re-prompts for screen
# capture. Falls back to ad-hoc ("-") on machines without the self-signed
# "Lens Dev" cert. Create one once via Keychain Access → Certificate Assistant
# → Create a Certificate → type "Code Signing".
SIGN_ID        := $(shell security find-certificate -c "Lens Dev" >/dev/null 2>&1 && echo "Lens Dev" || echo -)

# Size-optimised release flags:
#   -Osize         optimise for binary size over speed
#   -wmo           whole-module optimisation (better dead-code elimination)
#   -dead_strip    remove unreferenced symbols at link time
RELEASE_FLAGS  := -Xswiftc -Osize -Xswiftc -wmo -Xlinker -dead_strip

# appstage capture — pass APPSTAGE=1 to compile in the `--appstage <state>`
# driver (Sources/LensUI/AppStageCapture.swift, gated by -DAPPSTAGE). Off by
# default so production builds stay clean.
ifdef APPSTAGE
SWIFT_FLAGS += -Xswiftc -DAPPSTAGE
endif

BIN_PATH       = $(shell $(SWIFT) build -c $(CONFIG) --show-bin-path)

.PHONY: all build bundle run debug stop clean icon release dmg version bump test help

all: build

help:
	@echo "Targets:"
	@echo "  make build      — swift build -c release"
	@echo "  make bundle     — assemble Lens.app under build/ (signed)"
	@echo "  make run        — bundle + relaunch app"
	@echo "  make release    — clean size-optimised bundle, stripped + signed"
	@echo "  make debug      — debug build + run in foreground"
	@echo "  make icon       — render AppIcon.icns from AppIconRenderer"
	@echo "  make stop       — kill running Lens"
	@echo "  make clean      — swift package clean + remove build/"
	@echo "  make dmg        — drag-to-install disk image of the local bundle"
	@echo "  make version    — print Lens <short> (<build>)"
	@echo "  make bump       — increment CFBundleVersion"
	@echo ""
	@echo "  APPSTAGE=1      — compile in the --appstage capture driver"

build:
	$(SWIFT) build -c $(CONFIG) --product $(APP_NAME) $(RELEASE_FLAGS) $(SWIFT_FLAGS)

icon: build
	@rm -rf "$(ICONSET)"
	@if "$(BIN_PATH)/$(APP_NAME)" --icon "$(ICONSET)" >/dev/null 2>&1 && [ -d "$(ICONSET)" ]; then \
		iconutil -c icns "$(ICONSET)" -o "$(ICNS)"; \
		echo "→ $(ICNS) (regenerated)"; \
	elif [ -f "$(ICNS)" ]; then \
		echo "→ $(ICNS) (existing)"; \
	else \
		echo "⚠ no $(ICNS) yet — run after the icon renderer lands"; \
	fi

bundle: build
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(BIN_PATH)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(EXEC_NAME)"
	@cp "$(INFO_PLIST)" "$(APP_BUNDLE)/Contents/Info.plist"
	@if [ -f "$(ICNS)" ]; then cp "$(ICNS)" "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"; fi
	@$(STRIP) -x "$(APP_BUNDLE)/Contents/MacOS/$(EXEC_NAME)" 2>/dev/null || true
	@$(CODESIGN) --force --deep --sign "$(SIGN_ID)" \
		--entitlements "$(ENTITLEMENTS)" \
		"$(APP_BUNDLE)"
	@echo "→ $(APP_BUNDLE) ($$(du -sh "$(APP_BUNDLE)" | cut -f1), signed: $(SIGN_ID))"

release: clean bundle
	@echo "→ release bundle ready"

run: stop bundle
	@open "$(APP_BUNDLE)"
	@echo "→ launched $(APP_NAME)"

debug:
	$(SWIFT) build -c debug --product $(APP_NAME) $(SWIFT_FLAGS)
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(shell $(SWIFT) build -c debug --show-bin-path)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(EXEC_NAME)"
	@cp "$(INFO_PLIST)" "$(APP_BUNDLE)/Contents/Info.plist"
	@if [ -f "$(ICNS)" ]; then cp "$(ICNS)" "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"; fi
	@$(CODESIGN) --force --deep --sign "$(SIGN_ID)" --entitlements "$(ENTITLEMENTS)" "$(APP_BUNDLE)"
	@$(MAKE) stop
	@"$(APP_BUNDLE)/Contents/MacOS/$(EXEC_NAME)"

stop:
	@pkill -x $(EXEC_NAME) 2>/dev/null || true

clean:
	@$(SWIFT) package clean
	@rm -rf "$(BUILD_DIR)"
	@echo "→ cleaned"

version:
	@SHORT=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $(INFO_PLIST)); \
	BUILD=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" $(INFO_PLIST)); \
	echo "$(APP_NAME) $$SHORT ($$BUILD)"

bump:
	@CURRENT=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" $(INFO_PLIST)); \
	NEXT=$$(( CURRENT + 1 )); \
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$NEXT" $(INFO_PLIST); \
	echo "CFBundleVersion: $$CURRENT -> $$NEXT"

test:
	$(SWIFT) test

dmg: bundle
	@rm -rf build/dmg "$(DMG)"
	@mkdir -p build/dmg
	@cp -R "$(APP_BUNDLE)" build/dmg/
	@ln -s /Applications build/dmg/Applications
	@hdiutil create -volname "$(APP_NAME)" -srcfolder build/dmg -ov -format UDZO "$(DMG)" >/dev/null
	@rm -rf build/dmg
	@echo "→ $(DMG)"
