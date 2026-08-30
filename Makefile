APP_NAME := KeyboardHitCounter
APP_DIR := build/$(APP_NAME).app
ZIP := build/$(APP_NAME).zip
RESOURCES := Resources

# 分发产物必须是通用二进制，否则 Intel Mac 上拿到的 .app 跑不起来
UNIVERSAL := swift build -c release --arch arm64 --arch x86_64

.PHONY: build build-universal app zip run test clean icon

# 开发用：只构建宿主架构，比通用构建快一倍
build:
	swift build -c release

build-universal:
	$(UNIVERSAL)

app: build-universal
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources"
	cp "$$($(UNIVERSAL) --show-bin-path)/$(APP_NAME)" "$(APP_DIR)/Contents/MacOS/"
	cp "$(RESOURCES)/Info.plist" "$(APP_DIR)/Contents/"
	cp "$(RESOURCES)/$(APP_NAME).icns" "$(APP_DIR)/Contents/Resources/"
	codesign --force --deep --sign - "$(APP_DIR)"

# ditto 而非 zip：保留 .app 内的符号链接与扩展属性
zip: app
	rm -f "$(ZIP)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP_DIR)" "$(ZIP)"

run: app
	open "$(APP_DIR)"

test:
	swift test

clean:
	swift package clean
	rm -rf build

icon:
	swift Scripts/render_icon.swift build/icon_1024.png
	mkdir -p build/icon.iconset
	for s in 16 32 64 128 256 512; do \
		sips -z $$s $$s build/icon_1024.png --out build/icon.iconset/icon_$${s}x$${s}.png; \
		sips -z $$((s*2)) $$((s*2)) build/icon_1024.png --out build/icon.iconset/icon_$${s}x$${s}@2x.png; \
	done
	iconutil -c icns build/icon.iconset -o "$(RESOURCES)/$(APP_NAME).icns"
	rm -rf build/icon.iconset build/icon_1024.png
