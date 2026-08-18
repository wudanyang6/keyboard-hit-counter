import AppKit

public extension NSImage {
    /// 把图标转为 PNG Data（线程安全），供跨线程传递。
    func khcPNGData() -> Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }
}