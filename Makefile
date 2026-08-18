APP_NAME := KeyboardHitCounter
APP_DIR := build/$(APP_NAME).app
BIN_DIR := .build/release
RESOURCES := Resources

.PHONY: build app run test clean

build:
	swift build -c release

app: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS"
	cp "$(BIN_DIR)/$(APP_NAME)" "$(APP_DIR)/Contents/MacOS/"
	cp "$(RESOURCES)/Info.plist" "$(APP_DIR)/Contents/"
	codesign --force --deep --sign - "$(APP_DIR)"

run: app
	open "$(APP_DIR)"

test:
	swift test

clean:
	swift package clean
	rm -rf build