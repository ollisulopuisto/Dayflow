//
//  NetworkBlockingURLProtocol.swift
//  Dayflow
//
//  URLProtocol registered process-wide as the ultimate backstop for network
//  scope enforcement. Requests outside the selected scope fail immediately
//  without ever opening a network connection. This catches third-party SDKs
//  (analytics, updater, etc.) that create their own URLSession and bypass the
//  explicit `URLSession.shared` call sites guarded by `NetworkGate`.
//
//  When the selected scope allows a URL, `canInit` returns `false` and normal
//  network loading proceeds unimpeded.
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
    !NetworkAccessStore.shared.scope.allows(url)
  }

  override class func canInit(with task: URLSessionTask) -> Bool {
    guard let request = task.currentRequest ?? task.originalRequest else { return false }
    return canInit(with: request)
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

}
