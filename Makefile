export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
DERIVED := build

.PHONY: gen build test run open clean release notarize

gen:
	xcodegen generate

build: gen
	xcodebuild -scheme Lilt -configuration Debug -derivedDataPath $(DERIVED) build | tail -20

test: gen
	xcodebuild -scheme Lilt -configuration Debug -derivedDataPath $(DERIVED) test | tail -40

run: build
	open $(DERIVED)/Build/Products/Debug/Lilt.app

# A build for other people: Release, signed with Developer ID and the hardened runtime, zipped
# for notarization. `make notarize` then submits it, staples the ticket and re-zips.
RELEASE := build-release
APP := $(RELEASE)/Build/Products/Release/Lilt.app
ZIP := $(RELEASE)/Lilt.zip
# `xcrun notarytool store-credentials lilt-notary` creates this once (Apple ID + app-specific
# password, or an App Store Connect API key), kept in the keychain.
NOTARY_PROFILE := lilt-notary

release: gen
	xcodebuild -scheme Lilt -configuration Release -derivedDataPath $(RELEASE) build | tail -5
	codesign --verify --deep --strict --verbose=2 "$(APP)"
	rm -f "$(ZIP)"
	ditto -c -k --keepParent "$(APP)" "$(ZIP)"
	@echo "signed: $(APP)"

notarize: release
	xcrun notarytool submit "$(ZIP)" --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple "$(APP)"
	rm -f "$(ZIP)"
	ditto -c -k --keepParent "$(APP)" "$(ZIP)"
	spctl --assess --type execute --verbose=2 "$(APP)"
	@echo "notarized and stapled: $(ZIP)"
