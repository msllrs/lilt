export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
DERIVED := build

.PHONY: gen build test run open clean release notarize dmg

gen:
	xcodegen generate

build: gen
	xcodebuild -scheme Lilt -configuration Debug -derivedDataPath $(DERIVED) build | tail -20

test: gen
	xcodebuild -scheme Lilt -configuration Debug -derivedDataPath $(DERIVED) test | tail -40

run: build
	open $(DERIVED)/Build/Products/Debug/Lilt.app

# A build for other people: Release, signed with Developer ID and the hardened runtime, zipped
# for notarization. `make notarize` then submits it, staples the ticket and re-zips. `make dmg`
# then wraps the stapled app in a notarized disk image.
RELEASE := build-release
APP := $(RELEASE)/Build/Products/Release/Lilt.app
ZIP := $(RELEASE)/Lilt.zip
DMG := $(RELEASE)/Lilt.dmg
# `xcrun notarytool store-credentials lilt-notary` creates this once (Apple ID + app-specific
# password, or an App Store Connect API key), kept in the keychain.
NOTARY_PROFILE := lilt-notary

IDENTITY := Developer ID Application: LFSGD LTD (TKGBUP8TGN)
SPARKLE := $(APP)/Contents/Frameworks/Sparkle.framework
SIGN := codesign --force --options runtime --timestamp --sign "$(IDENTITY)"

release: gen
	xcodebuild -scheme Lilt -configuration Release -derivedDataPath $(RELEASE) build | tail -5
	# Sparkle's helpers ship ad hoc signed and Xcode only re-seals the framework around them,
	# which notarization rejects. Sign them with our identity, inside out, keeping their own
	# entitlements, then re-seal the framework and the app with the entitlements it was built with.
	$(SIGN) --preserve-metadata=entitlements \
		"$(SPARKLE)/Versions/B/XPCServices/Installer.xpc" \
		"$(SPARKLE)/Versions/B/XPCServices/Downloader.xpc" \
		"$(SPARKLE)/Versions/B/Autoupdate" \
		"$(SPARKLE)/Versions/B/Updater.app"
	$(SIGN) "$(SPARKLE)"
	codesign -d --entitlements "$(RELEASE)/entitlements.plist" --xml "$(APP)"
	$(SIGN) --entitlements "$(RELEASE)/entitlements.plist" "$(APP)"
	codesign --verify --deep --strict --verbose=2 "$(APP)"
	rm -f "$(ZIP)"
	ditto -c -k --keepParent "$(APP)" "$(ZIP)"
	@echo "signed: $(APP)"

# Submits, waits, and only staples when Apple accepted; a rejection prints Apple's log.
notarize: release
	xcrun notarytool submit "$(ZIP)" --keychain-profile $(NOTARY_PROFILE) --wait --output-format json > "$(RELEASE)/notarize.json"; \
	status=$$(/usr/bin/plutil -extract status raw -o - "$(RELEASE)/notarize.json"); id=$$(/usr/bin/plutil -extract id raw -o - "$(RELEASE)/notarize.json"); \
	echo "notarization $$status ($$id)"; \
	if [ "$$status" != "Accepted" ]; then xcrun notarytool log $$id --keychain-profile $(NOTARY_PROFILE); exit 1; fi
	xcrun stapler staple "$(APP)"
	rm -f "$(ZIP)"
	ditto -c -k --keepParent "$(APP)" "$(ZIP)"
	spctl --assess --type execute --verbose=2 "$(APP)"
	@echo "notarized and stapled: $(ZIP)"

# A disk image of the app `make notarize` stapled, with an Applications link to drag it onto.
# The image is signed and notarized itself, so it opens cleanly offline too.
dmg:
	xcrun stapler validate "$(APP)"
	rm -rf "$(RELEASE)/dmg" "$(DMG)"
	mkdir "$(RELEASE)/dmg"
	ditto "$(APP)" "$(RELEASE)/dmg/Lilt.app"
	ln -s /Applications "$(RELEASE)/dmg/Applications"
	hdiutil create -volname Lilt -srcfolder "$(RELEASE)/dmg" -fs HFS+ -format UDZO -ov "$(DMG)"
	rm -rf "$(RELEASE)/dmg"
	codesign --force --timestamp --sign "$(IDENTITY)" "$(DMG)"
	xcrun notarytool submit "$(DMG)" --keychain-profile $(NOTARY_PROFILE) --wait --output-format json > "$(RELEASE)/notarize-dmg.json"; \
	status=$$(/usr/bin/plutil -extract status raw -o - "$(RELEASE)/notarize-dmg.json"); id=$$(/usr/bin/plutil -extract id raw -o - "$(RELEASE)/notarize-dmg.json"); \
	echo "notarization $$status ($$id)"; \
	if [ "$$status" != "Accepted" ]; then xcrun notarytool log $$id --keychain-profile $(NOTARY_PROFILE); exit 1; fi
	xcrun stapler staple "$(DMG)"
	spctl --assess --type open --context context:primary-signature --verbose=2 "$(DMG)"
	@echo "notarized and stapled: $(DMG)"
