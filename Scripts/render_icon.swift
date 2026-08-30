import AppKit

/// 渲染 App 图标：蓝色渐变圆角底 + 居中白色 SF Symbol「keyboard」，输出 1024×1024 PNG。
/// 用法：swift Scripts/render_icon.swift <输出PNG路径>

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon_1024.png"

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// 1. 圆角背景 + 自上而下的蓝色渐变
let bgRect = NSRect(x: 0, y: 0, width: canvas, height: canvas)
let bgPath = NSBezierPath(
    roundedRect: bgRect,
    xRadius: canvas * 0.22,
    yRadius: canvas * 0.22
)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.29, green: 0.62, blue: 1.00, alpha: 1),
    ending: NSColor(calibratedRed: 0.02, green: 0.36, blue: 0.90, alpha: 1)
)!
gradient.draw(in: bgPath, angle: -90)

// 2. 居中的白色 SF Symbol
if let symbol = whiteSymbol(named: "keyboard", pointSize: 640) {
    let rect = NSRect(
        x: (canvas - symbol.size.width) / 2,
        y: (canvas - symbol.size.height) / 2,
        width: symbol.size.width,
        height: symbol.size.height
    )
    symbol.draw(in: rect)
}

image.unlockFocus()

// 3. 编码为 PNG 写出
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("无法编码 PNG\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outputPath))
print(outputPath)

/// 把模板 SF Symbol 染成白色：先在透明画布绘制，再用 sourceAtop 叠加白色。
private func whiteSymbol(named name: String, pointSize: CGFloat) -> NSImage? {
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)) else {
        return nil
    }
    let size = symbol.size
    return NSImage(size: size, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
}
