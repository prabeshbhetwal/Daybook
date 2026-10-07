import CoreGraphics
import Foundation
import ImageIO

// swift scripts/compare-snapshots.swift <dirA> <dirB>
//
// Compares the PNGs of two snapshot folders by file name. An image fails when
// any channel of any pixel differs by more than 1/255, or when more than 8
// pixels differ at all (one-step noise in a handful of pixels is tolerated).
// Prints one line per failing or missing file and a summary; exits 1 when any
// image fails or is missing from <dirB>, and 2 when <dirA> holds no PNGs (a
// comparison against nothing would pass vacuously).

/// The image as 8-bit sRGB RGBA, so two files compare the same way whatever
/// colour profile each was written with.
func pixels(_ url: URL) -> (width: Int, height: Int, bytes: [UInt8])? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return drawn ? (width, height, bytes) : nil
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: swift scripts/compare-snapshots.swift <dirA> <dirB>")
    exit(2)
}
let manager = FileManager.default
let names = ((try? manager.contentsOfDirectory(atPath: arguments[1])) ?? []).filter { $0.hasSuffix(".png") }.sorted()
guard !names.isEmpty else {
    print("error: no PNGs in \(arguments[1])")
    exit(2)
}
var compared = 0, differ = 0, missing = 0
for name in names {
    let pathA = (arguments[1] as NSString).appendingPathComponent(name)
    let pathB = (arguments[2] as NSString).appendingPathComponent(name)
    guard manager.fileExists(atPath: pathB) else { print("missing: \(name)"); missing += 1; continue }
    compared += 1
    if manager.contentsEqual(atPath: pathA, andPath: pathB) { continue }
    guard let a = pixels(URL(fileURLWithPath: pathA)), let b = pixels(URL(fileURLWithPath: pathB)) else {
        print("unreadable: \(name)"); differ += 1; continue
    }
    guard a.width == b.width, a.height == b.height else {
        print("\(name): \(a.width)x\(a.height) against \(b.width)x\(b.height)"); differ += 1; continue
    }
    var changed = 0, largest = 0
    for index in stride(from: 0, to: a.bytes.count, by: 4) {
        var worst = 0
        for channel in 0..<4 { worst = max(worst, abs(Int(a.bytes[index + channel]) - Int(b.bytes[index + channel]))) }
        if worst > 0 { changed += 1; largest = max(largest, worst) }
    }
    if largest > 1 || changed > 8 {
        print("\(name): \(changed) pixels differ, largest channel step \(largest)/255")
        differ += 1
    }
}
print("\(compared) compared, \(differ) differ, \(missing) missing")
exit(differ + missing > 0 ? 1 : 0)
