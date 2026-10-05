export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
DERIVED := build

.PHONY: gen build test run open clean native

gen:
	xcodegen generate

build: gen
	xcodebuild -scheme Lilt -configuration Debug -derivedDataPath $(DERIVED) build | tail -20

test: gen
	xcodebuild -scheme Lilt -configuration Debug -derivedDataPath $(DERIVED) test | tail -40

run: build
	open $(DERIVED)/Build/Products/Debug/Lilt.app

# The native-frame experiment as a second app ("Lilt Native", its own bundle id and container),
# so it can run beside the regular build for comparison.
NATIVE := build-native
native: gen
	xcodebuild -scheme Lilt -configuration Debug -derivedDataPath $(NATIVE) build \
		PRODUCT_NAME="Lilt Native" PRODUCT_MODULE_NAME=Lilt PRODUCT_BUNDLE_IDENTIFIER=com.msllrs.LiltNative \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG NATIVE_FRAME" | tail -5
	/usr/libexec/PlistBuddy -c "Set :CFBundleName Lilt Native" -c "Set :CFBundleDisplayName Lilt Native" "$(NATIVE)/Build/Products/Debug/Lilt Native.app/Contents/Info.plist"
	codesign --force --sign - --entitlements Config/Lilt.entitlements "$(NATIVE)/Build/Products/Debug/Lilt Native.app"
	open "$(NATIVE)/Build/Products/Debug/Lilt Native.app"

open: gen
	open Lilt.xcodeproj

clean:
	rm -rf $(DERIVED)
