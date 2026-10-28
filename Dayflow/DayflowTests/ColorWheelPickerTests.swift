import XCTest

@testable import Dayflow

final class ColorWheelPickerTests: XCTestCase {
  func testHSLToRGBPrimaryColors() {
    let accuracy = 0.001

    // Red: H=0, S=100%, L=50%
    let red = hslToRGB(0, 100, 50)
    XCTAssertEqual(red.r, 1.0, accuracy: accuracy)
    XCTAssertEqual(red.g, 0.0, accuracy: accuracy)
    XCTAssertEqual(red.b, 0.0, accuracy: accuracy)

    // Green: H=120, S=100%, L=50%
    let green = hslToRGB(120, 100, 50)
    XCTAssertEqual(green.r, 0.0, accuracy: accuracy)
    XCTAssertEqual(green.g, 1.0, accuracy: accuracy)
    XCTAssertEqual(green.b, 0.0, accuracy: accuracy)

    // Blue: H=240, S=100%, L=50%
    let blue = hslToRGB(240, 100, 50)
    XCTAssertEqual(blue.r, 0.0, accuracy: accuracy)
    XCTAssertEqual(blue.g, 0.0, accuracy: accuracy)
    XCTAssertEqual(blue.b, 1.0, accuracy: accuracy)
  }

  func testHSLToRGBSecondaryColors() {
    let accuracy = 0.001

    // Yellow: H=60, S=100%, L=50%
    let yellow = hslToRGB(60, 100, 50)
    XCTAssertEqual(yellow.r, 1.0, accuracy: accuracy)
    XCTAssertEqual(yellow.g, 1.0, accuracy: accuracy)
    XCTAssertEqual(yellow.b, 0.0, accuracy: accuracy)

    // Cyan: H=180, S=100%, L=50%
    let cyan = hslToRGB(180, 100, 50)
    XCTAssertEqual(cyan.r, 0.0, accuracy: accuracy)
    XCTAssertEqual(cyan.g, 1.0, accuracy: accuracy)
    XCTAssertEqual(cyan.b, 1.0, accuracy: accuracy)

    // Magenta: H=300, S=100%, L=50%
    let magenta = hslToRGB(300, 100, 50)
    XCTAssertEqual(magenta.r, 1.0, accuracy: accuracy)
    XCTAssertEqual(magenta.g, 0.0, accuracy: accuracy)
    XCTAssertEqual(magenta.b, 1.0, accuracy: accuracy)
  }

  func testHSLToRGBExtremeValuesAndAchromaticGrays() {
    let accuracy = 0.001

    // Black: L=0%
    let black = hslToRGB(0, 100, 0)
    XCTAssertEqual(black.r, 0.0, accuracy: accuracy)
    XCTAssertEqual(black.g, 0.0, accuracy: accuracy)
    XCTAssertEqual(black.b, 0.0, accuracy: accuracy)

    // White: L=100%
    let white = hslToRGB(0, 100, 100)
    XCTAssertEqual(white.r, 1.0, accuracy: accuracy)
    XCTAssertEqual(white.g, 1.0, accuracy: accuracy)
    XCTAssertEqual(white.b, 1.0, accuracy: accuracy)

    // Gray: S=0%, L=50%
    let gray = hslToRGB(0, 0, 50)
    XCTAssertEqual(gray.r, 0.5, accuracy: accuracy)
    XCTAssertEqual(gray.g, 0.5, accuracy: accuracy)
    XCTAssertEqual(gray.b, 0.5, accuracy: accuracy)
  }

  func testHSLToRGBHueNormalization() {
    let accuracy = 0.001

    // Negative hue: -120° should normalize to 240° (Blue)
    let negHue = hslToRGB(-120, 100, 50)
    let blue = hslToRGB(240, 100, 50)
    XCTAssertEqual(negHue.r, blue.r, accuracy: accuracy)
    XCTAssertEqual(negHue.g, blue.g, accuracy: accuracy)
    XCTAssertEqual(negHue.b, blue.b, accuracy: accuracy)

    // Overflow hue: 480° should normalize to 120° (Green)
    let overflowHue = hslToRGB(480, 100, 50)
    let green = hslToRGB(120, 100, 50)
    XCTAssertEqual(overflowHue.r, green.r, accuracy: accuracy)
    XCTAssertEqual(overflowHue.g, green.g, accuracy: accuracy)
    XCTAssertEqual(overflowHue.b, green.b, accuracy: accuracy)
  }

  func testHSLToRGBClamping() {
    let accuracy = 0.001

    // Saturation > 100% should clamp to 100%
    let clampedSat = hslToRGB(0, 150, 50)
    let expectedSat = hslToRGB(0, 100, 50)
    XCTAssertEqual(clampedSat.r, expectedSat.r, accuracy: accuracy)

    // Saturation < 0% should clamp to 0%
    let clampedNegSat = hslToRGB(0, -50, 50)
    let expectedNegSat = hslToRGB(0, 0, 50)
    XCTAssertEqual(clampedNegSat.r, expectedNegSat.r, accuracy: accuracy)

    // Lightness > 100% should clamp to 100%
    let clampedLight = hslToRGB(0, 100, 200)
    let expectedLight = hslToRGB(0, 100, 100)
    XCTAssertEqual(clampedLight.r, expectedLight.r, accuracy: accuracy)

    // Lightness < 0% should clamp to 0%
    let clampedNegLight = hslToRGB(0, 100, -50)
    let expectedNegLight = hslToRGB(0, 100, 0)
    XCTAssertEqual(clampedNegLight.r, expectedNegLight.r, accuracy: accuracy)
  }

  func testHSLToHexFormatting() {
    XCTAssertEqual(hslToHex(0, 100, 50), "#FF0000")
    XCTAssertEqual(hslToHex(120, 100, 50), "#00FF00")
    XCTAssertEqual(hslToHex(240, 100, 50), "#0000FF")
    XCTAssertEqual(hslToHex(0, 0, 0), "#000000")
    XCTAssertEqual(hslToHex(0, 0, 100), "#FFFFFF")
  }
}
