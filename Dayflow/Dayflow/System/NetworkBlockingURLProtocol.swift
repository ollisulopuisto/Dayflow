//
//  NetworkBlockingURLProtocol.swift
//  Dayflow
//
//  URLProtocol registered process-wide as the ultimate backstop for
//  "local access only" hardening. When outside-network permission has NOT been
//  granted, every http/https request to a non-local host is failed immediately
//  without ever opening a network connection. This catches third-party SDKs
//  (analytics, updater, etc.) that create their own URLSession and bypass the
//  explicit `URLSession.shared` call sites guarded by `NetworkGate`.
//
//  When permission IS granted, `canInit` returns `false` for everything, so
//  normal network loading proceeds unimpeded.
//

import Foundation

final class NetworkBlockingURLProtocol: URLProtocol {
  static let blockedError = URLError(.notConnectedToInternet)

  override class func canInit(with request: URLRequest) -> Bool {
    // Only http/https can reach the outside network.
    guard let url = request.url,
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else {
      return false
    }
    // Localhost / link-local is local access: never block.
    if Self.isLocalHost(url) { return false }
    // Permission granted: let everything load normally.
    if NetworkAccessStore.shared.isAllowed { return false }
    // No permission: block this outside request.
    return true
  }

  override class func canInit(with task: URLSessionTask) -> Bool {
    // We handle requests at the request level; task-level init is not needed.
    false
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    // We only ever get here when `canInit` returned true, i.e. we are blocking.
    // Fail immediately without opening any network connection.
    client?.urlProtocol(
      self,
      didFailWithError: NetworkBlockingURLProtocol.blockedError
    )
  }

  override func stopLoading() {
    // Nothing in flight; we never open a real connection.
  }

  private static func isLocalHost(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return true }
    return host == "localhost" || host == "127.0.0.1" || host == "::1"
  }
}
