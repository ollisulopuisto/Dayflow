import XCTest

@testable import Dayflow

/// This fork's Privacy Shield masks with the pattern rules alone (upstream's paid model is gone):
/// these tests pin what the rules must hide and what they must leave alone when every model score
/// is zero, which is exactly how the recorder's masker calls them now.
final class PrivacyShieldRulesTests: XCTestCase {
  private let rules = PIIMaskRules(threshold: 0.5, bip39Words: BIP39Wordlist.words)

  /// One label per code point per line, with no model input at all.
  private func labels(for lines: [String]) -> [[Int]] {
    let ocr = lines.map { PIIOCRLine(text: $0, box: .zero) }
    rules.apply(
      lines: ocr,
      sensitive: lines.map { [Float](repeating: 0, count: $0.unicodeScalars.count) },
      best: lines.map { [Int](repeating: 0, count: $0.unicodeScalars.count) })
  }

  /// The masked (nonzero-label) character runs of one line's predictions.
  private func maskedRuns(_ line: String, _ pred: [Int]) -> [String] {
    let scalars = Array(line.unicodeScalars)
    XCTAssertEqual(scalars.count, pred.count)
    var runs: [String] = []
    var i = 0
    while i < pred.count {
      guard pred[i] != 0 else { i += 1; continue }
      var j = i
      while j < pred.count && pred[j] == pred[i] { j += 1 }
      runs.append(String(String.UnicodeScalarView(scalars[i..<j])))
      i = j
    }
    return runs
  }

  private func assertMasked(_ needle: String, in lines: [String], file: StaticString = #filePath, line: UInt = #line) {
    let preds = labels(for: lines)
    let haystack = lines.joined(separator: "\n")
    guard let lineIndex = lines.firstIndex(where: { $0.contains(needle) }) else {
      XCTFail("needle not in input", file: file, line: line)
      return
    }
    let runs = maskedRuns(lines[lineIndex], preds[lineIndex])
    XCTAssertTrue(
      runs.contains(where: { $0.contains(needle) }),
      "\(needle) not masked in \(haystack); runs: \(runs)", file: file, line: line)
  }

  private func assertNothingMasked(in lines: [String], file: StaticString = #filePath, line: UInt = #line) {
    let preds = labels(for: lines)
    for (index, pred) in preds.enumerated() {
      XCTAssertEqual(
        Set(pred), [0], "unexpected mask on \"\(lines[index])\"", file: file, line: line)
    }
  }

  // MARK: - What must be masked

  func testKnownAPIKeyPrefixesAreMasked() {
    assertMasked("sk-proj-AbC123xYz_4567890", in: ["OPENAI_API_KEY=sk-proj-AbC123xYz_4567890"])
    assertMasked("ghp_abcdefghijklmnop1234", in: ["token: ghp_abcdefghijklmnop1234"])
    assertMasked("AKIAIOSFODNN7EXAMPLE", in: ["aws: AKIAIOSFODNN7EXAMPLE"])
  }

  func testPrivateKeyBlockIsMasked() {
    assertMasked(
      "MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwgg",
      in: [
        "-----BEGIN RSA PRIVATE KEY-----",
        "MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwgg",
        "SkJmQ5Z3K0EXAMPLE7bq2ScusSgXOUFflK",
        "-----END RSA PRIVATE KEY-----",
      ])
  }

  func testLabeledPasswordIsMasked() {
    assertMasked("Tr0ub4dor!3", in: ["Password: Tr0ub4dor!3"])
  }

  func testCLIPasswordFlagIsMasked() {
    assertMasked("s3cretpw", in: ["mysql -u root -p s3cretpw --host db"])
  }

  func testTOTPSetupKeyIsMasked() {
    assertMasked("JBSW Y3DP EHPK 3PXP", in: ["JBSW Y3DP EHPK 3PXP"])
  }

  func testGroupedCardNumberWithValidLuhnIsMasked() {
    assertMasked("4242 4242 4242 4242", in: ["4242 4242 4242 4242"])
  }

  func testUngroupedCardNumberNeedsContext() {
    assertMasked("4242424242424242", in: ["Card number: 4242424242424242"])
    assertNothingMasked(in: ["tracking 4242424242424242 done"])
  }

  func testCardWithBrokenLuhnIsNotMasked() {
    assertNothingMasked(in: ["4242 4242 4242 4243"])
  }

  func testValidIBANIsMasked() {
    assertMasked("FI21 1234 5600 0007 85", in: ["IBAN: FI21 1234 5600 0007 85"])
  }

  func testIBANWithBrokenChecksumIsNotMasked() {
    assertNothingMasked(in: ["FI21 1234 5600 0007 86"])
  }

  func testSeedPhraseWithRecoveryContextIsMasked() {
    // Each seed word is its own masked run (spaces stay readable), so check single words.
    let lines = [
      "Recovery phrase",
      "abandon ability able about",
      "above absent absorb abstract",
      "abstract absurd abuse access",  // 12 words total across the block
    ]
    assertMasked("abandon", in: lines)
    assertMasked("absorb", in: lines)
    assertMasked("access", in: lines)
  }

  // MARK: - What must stay readable

  func testOrdinaryScreenTextIsNotMasked() {
    assertNothingMasked(in: [
      "Meeting at 12:30 tomorrow",
      "Visit https://example.com/docs for details",
      "Order 12345678 confirmed",
      "Lähetys saapuu perjantaina",
    ])
  }
}

/// The bundled BIP39 list must stay the real 2,048-word standard list.
final class BIP39WordlistTests: XCTestCase {
  func testListIsCompleteSortedAndUnique() {
    XCTAssertEqual(BIP39Wordlist.words.count, 2048)
    XCTAssertEqual(Set(BIP39Wordlist.words).count, 2048)
    XCTAssertEqual(BIP39Wordlist.words, BIP39Wordlist.words.sorted())
    XCTAssertEqual(BIP39Wordlist.words.first, "abandon")
    XCTAssertEqual(BIP39Wordlist.words.last, "zoo")
  }
}
