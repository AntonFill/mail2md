//
//  InlineImages.swift
//  mail2md
//
//  Created by Anton Fillmann on 04.10.2026.
//

import Foundation
import ImageIO

/// A picture an HTML body shows from a part of its own mail, addressed by
/// `cid:` (RFC 2392), with the size the HTML gives it.
///
/// Which of these pictures is content and which a logo cannot be told from the
/// mail: measured on 2026-10-03 over 716 mails, social icons were stored at
/// 2636 × 2636 pixels and signature banners had the shape of screenshots, and
/// no rule from size, shape or link sorted all of them. So the tool does not
/// decide it (Anton's decision a). The note leaves the pictures out and the
/// run names them, or, on request, every picture is written as a file and
/// embedded where it stands, and whoever reads the note keeps what is content.
struct InlineImage: Equatable {

    /// The `Content-ID` of the part the picture is addressed by, without its
    /// angle brackets.
    let contentID: String

    /// The width and the height the HTML gives the picture, in CSS pixels: in
    /// its inline style, which a browser lets win, else in its attributes. Nil
    /// where it gives none that a browser could resolve without the page
    /// around it, a share of the page or `auto`.
    let width: Int?
    let height: Int?
}

/// A width and a height in pixels.
struct PixelSize: Equatable {
    let width: Int
    let height: Int
}

// MARK: - Size
extension InlineImage {

    /// The size a browser shows the picture at: the one the HTML gives it, a
    /// side it leaves open in the picture's own proportion, and the picture's
    /// own size where it gives none. Nil where that needs the picture's own
    /// size and there is none.
    func displaySize(natural: PixelSize?) -> PixelSize? {
        if let width = self.width, let height = self.height {
            return PixelSize(width: width, height: height)
        }
        guard
            let natural,
            natural.width > 0,
            natural.height > 0
        else {
            return nil
        }

        if let width = self.width {
            let height = Double(width) * Double(natural.height) / Double(natural.width)
            return PixelSize(width: width, height: Int(height.rounded()))
        }
        if let height = self.height {
            let width = Double(height) * Double(natural.width) / Double(natural.height)
            return PixelSize(width: Int(width.rounded()), height: height)
        }
        return natural
    }
}

extension PixelSize {

    /// The size the header of a picture states, read through ImageIO. Nil for
    /// bytes it cannot read as a picture, an SVG among them.
    init?(of data: Data) {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }

        self.init(width: width, height: height)
    }
}

// MARK: - The report
extension InlineImage {

    /// A picture the note leaves out, as the run names it: by the name its
    /// part carries, with the size a browser shows it at where that is known.
    struct Omission: Equatable {
        let name: String
        let size: PixelSize?
    }

    /// One line naming every picture left out, in the order the body shows
    /// them: `inline images left out: image001.png 474×464, logo.svg`. The size
    /// is the hint whether a picture is worth fetching, a screenshot or an icon.
    static func summary(_ omissions: [Omission]) -> String {
        let listing = omissions.map { omission in
            guard let size = omission.size else {
                return omission.name
            }
            return "\(omission.name) \(size.width)×\(size.height)"
        }

        return "inline images left out: \(listing.joined(separator: ", "))"
    }
}
