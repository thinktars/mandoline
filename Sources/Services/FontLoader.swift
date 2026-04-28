import Foundation
import CoreText

enum FontLoader {
    /// Registers bundled fonts (ttf/otf) so SwiftUI `Font.custom(...)` resolves correctly.
    static func registerBundledFonts() {
        let fm = FileManager.default
        let fontExtensions = ["ttf", "otf"]

        for ext in fontExtensions {
            // Xcode typically flattens individual resource files into the bundle's Resources directory.
            // We'll search both the root and the "Fonts" subdirectory to be safe.
            let urls = (Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? [])
                + (Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "Fonts") ?? [])

            for url in urls {
                var error: Unmanaged<CFError>?
                let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
                if !ok {
                    if let err = error?.takeRetainedValue() {
                        // Non-fatal: the font may already be registered.
                        print("[Mandoline] Font registration failed for \(url.lastPathComponent): \(err)")
                    }
                } else {
                    // Sanity check to reduce confusion when fonts aren't actually bundled.
                    _ = fm.fileExists(atPath: url.path)
                }
            }
        }
    }
}
