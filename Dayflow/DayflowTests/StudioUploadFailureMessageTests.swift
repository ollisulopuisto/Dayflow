import XCTest

@testable import Dayflow

final class StudioUploadFailureMessageTests: XCTestCase {
  private let httpEndpoint = URL(string: "http://mac-studio.example.ts.net:18765")!
  private let httpsEndpoint = URL(string: "https://mac-studio.example.ts.net:18765")!

  func testTransportSecurityBlockPointsAtLocalAndTailscaleAddresses() {
    let message = StudioBatchQueue.describeUploadFailure(
      error: URLError(.appTransportSecurityRequiresSecureConnection),
      statusCode: nil,
      endpoint: httpEndpoint)
    XCTAssertTrue(message.contains("Tailscale"))
  }

  func testSecureConnectionFailureAgainstHTTPSURLExplainsPlainHTTPService() {
    let message = StudioBatchQueue.describeUploadFailure(
      error: URLError(.secureConnectionFailed),
      statusCode: nil,
      endpoint: httpsEndpoint)
    XCTAssertTrue(message.contains("plain HTTP"))
  }

  func testSecureConnectionFailureOnHTTPURLKeepsBaseMessage() {
    let error = URLError(.secureConnectionFailed)
    let message = StudioBatchQueue.describeUploadFailure(
      error: error,
      statusCode: nil,
      endpoint: httpEndpoint)
    XCTAssertEqual(message, error.localizedDescription)
  }

  func testNonURLErrorKeepsBaseMessage() {
    struct SampleError: Error {}
    let message = StudioBatchQueue.describeUploadFailure(
      error: SampleError(),
      statusCode: nil,
      endpoint: httpEndpoint)
    XCTAssertFalse(message.contains("plain HTTP"))
    XCTAssertFalse(message.contains("Tailscale"))
  }

  func testMissingErrorReportsHTTPStatus() {
    let message = StudioBatchQueue.describeUploadFailure(
      error: nil,
      statusCode: 503,
      endpoint: httpEndpoint)
    XCTAssertEqual(message, "Studio returned HTTP 503")
  }
}
