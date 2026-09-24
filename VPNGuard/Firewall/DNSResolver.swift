//
//  DNSResolver.swift
//  VPNGuard
//
//  Resolves protected hostnames to IPv4 and IPv6 addresses using CFHost.
//

import Foundation

final class DNSResolver: Sendable {

    static let shared = DNSResolver()

    private init() {}

    /// Resolves a hostname to all IP addresses (IPv4 and IPv6).
    ///
    /// Bounded by `timeout`: a stuck resolver (common after wake with broken
    /// DNS) yields no addresses instead of blocking the caller forever.
    func resolve(host: String, timeout: TimeInterval = Constants.dnsTimeout) async -> [String] {
        let addresses = await Timeout.race(seconds: timeout) {
            await self.lookupOffMain(host: host)
        }

        if addresses == nil {
            Logger.shared.error("DNS resolution timed out", details: ["Host": host])
        }
        return addresses ?? []
    }

    // MARK: - Private

    private func lookupOffMain(host: String) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.lookup(host: host))
            }
        }
    }

    private func lookup(host: String) -> [String] {
        var result: [String] = []

        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var info: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &info)
        guard status == 0, let first = info else {
            Logger.shared.error("DNS resolution failed", details: [
                "Host": host,
                "Error": String(cString: gai_strerror(status))
            ])
            return result
        }

        defer { freeaddrinfo(info) }

        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let current = cursor {
            if let addr = current.pointee.ai_addr {
                if let ip = formatAddress(addr, length: current.pointee.ai_addrlen) {
                    result.append(ip)
                }
            }
            cursor = current.pointee.ai_next
        }

        return Array(Set(result))
    }

    private func formatAddress(_ addr: UnsafePointer<sockaddr>, length: socklen_t) -> String? {
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            addr,
            length,
            &hostBuffer,
            socklen_t(hostBuffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard result == 0 else { return nil }
        return String(cString: hostBuffer)
    }
}
