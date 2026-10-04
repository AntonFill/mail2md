//
//  InlineImagesTests.swift
//  mail2md
//
//  Created by Anton Fillmann on 04.10.2026.
//

import Foundation
import Testing
@testable import mail2md

/// The size a picture is shown at, and the line that names what a note leaves
/// out. The screenshot of the mail behind the work is stored at 819 × 801.
struct InlineImagesTests {

    static let screenshot = PixelSize(width: 819, height: 801)

    /// Both sides given, a browser stretches the picture to them, also out of
    /// its own proportion.
    @Test func takesTheSizeTheHTMLGives() {
        let image = InlineImage(contentID: "image001.png@01DC", width: 474, height: 100)

        #expect(image.displaySize(natural: Self.screenshot) == PixelSize(width: 474, height: 100))
    }

    /// A browser keeps the picture's proportion for the side the HTML leaves
    /// open: 474 × 801 / 819 and 464 × 819 / 801, rounded.
    @Test(arguments: [
        (474, nil, PixelSize(width: 474, height: 464)),
        (nil, 464, PixelSize(width: 474, height: 464)),
    ] as [(Int?, Int?, PixelSize)])
    func scalesTheOpenSideInProportion(width: Int?, height: Int?, expected: PixelSize) {
        let image = InlineImage(contentID: "image001.png@01DC", width: width, height: height)

        #expect(image.displaySize(natural: Self.screenshot) == expected)
    }

    @Test func takesThePicturesOwnSizeWhereTheHTMLGivesNone() {
        let image = InlineImage(contentID: "image001.png@01DC", width: nil, height: nil)

        #expect(image.displaySize(natural: Self.screenshot) == Self.screenshot)
    }

    /// Without the picture's own size an open side cannot be worked out, and
    /// a picture without width or without height has no proportion to keep.
    @Test(arguments: [
        (474, nil, nil),
        (nil, nil, nil),
        (474, nil, PixelSize(width: 0, height: 10)),
        (nil, 464, PixelSize(width: 10, height: 0)),
    ] as [(Int?, Int?, PixelSize?)])
    func knowsNoSizeItCannotWorkOut(width: Int?, height: Int?, natural: PixelSize?) {
        let image = InlineImage(contentID: "image001.png@01DC", width: width, height: height)

        #expect(image.displaySize(natural: natural) == nil)
    }

    /// The size a picture's own header states, read through ImageIO, and none
    /// for bytes that are no picture.
    @Test func readsThePixelSizeFromThePicturesHeader() throws {
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAAAAAC4HznGAAAAD0lEQVR4nGM4ceIEAxADABLIBLEaJ2FIAAAAAElFTkSuQmCC"))

        #expect(PixelSize(of: png) == PixelSize(width: 3, height: 2))
        #expect(PixelSize(of: Data("no picture".utf8)) == nil)
    }

    @Test func namesEveryPictureLeftOutWithTheSizeItIsShownAt() {
        let line = InlineImage.summary([
            InlineImage.Omission(name: "image001.png", size: PixelSize(width: 474, height: 464)),
            InlineImage.Omission(name: "logo.svg", size: nil),
        ])

        #expect(line == "inline images left out: image001.png 474×464, logo.svg")
    }
}
