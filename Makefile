export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
DERIVED := build

.PHONY: gen build test run open clean

gen:
	xcodegen generate

build: gen
	xcodebuild -scheme Lilt -configuration Debug -derivedDataPath $(DERIVED) build | tail -20

test: gen
	xcodebuild -scheme Lilt -configuration Debug -derivedDataPath $(DERIVED) test | tail -40

run: build
	open $(DERIVED)/Build/Products/Debug/Lilt.app

open: gen
	open Lilt.xcodeproj

clean:
	rm -rf $(DERIVED)
