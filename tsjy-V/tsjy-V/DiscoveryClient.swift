import Foundation
import Network

@MainActor
final class DiscoveryClient: NSObject {
    var onGatewaysChanged: (([DiscoveredGateway]) -> Void)?

    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var gateways: [DiscoveredGateway] = []

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        services.removeAll()
        gateways.removeAll()
        browser.searchForServices(ofType: TSJYNetwork.bonjourType, inDomain: "local.")
    }

    func stop() {
        browser.stop()
        services.forEach { $0.stop() }
        services.removeAll()
        gateways.removeAll()
        onGatewaysChanged?([])
    }
}

extension DiscoveryClient: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.resolve(withTimeout: 5)
        services.append(service)
        if !moreComing {
            onGatewaysChanged?(gateways)
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 == service }
        gateways.removeAll { $0.name == service.name }
        if !moreComing {
            onGatewaysChanged?(gateways)
        }
    }
}

extension DiscoveryClient: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        let host = resolvedHost(for: sender)
            ?? sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard let host else {
            return
        }

        let txtRecord = sender.txtRecordData().flatMap(NetService.dictionary(fromTXTRecord:)) ?? [:]
        let videoPort = Int(String(data: txtRecord["videoPort"] ?? Data(), encoding: .utf8) ?? "8800") ?? 8800
        let controlPort = Int(String(data: txtRecord["controlPort"] ?? Data(), encoding: .utf8) ?? "8801") ?? 8801
        let gateway = DiscoveredGateway(name: sender.name, host: host, controlPort: controlPort, videoPort: videoPort)

        if let index = gateways.firstIndex(where: { $0.name == gateway.name && $0.host == gateway.host }) {
            gateways[index] = gateway
        } else {
            gateways.append(gateway)
        }
        gateways.sort { $0.name < $1.name }
        onGatewaysChanged?(gateways)
    }

    private func resolvedHost(for service: NetService) -> String? {
        guard let addresses = service.addresses else { return nil }
        for address in addresses {
            if let ipv4 = ipv4String(from: address) {
                return ipv4
            }
        }
        for address in addresses {
            if let ipv6 = ipv6String(from: address) {
                return ipv6
            }
        }
        return nil
    }

    private func ipv4String(from data: Data) -> String? {
        data.withUnsafeBytes { rawBuffer in
            guard let sockaddr = rawBuffer.baseAddress?.assumingMemoryBound(to: sockaddr.self),
                  sockaddr.pointee.sa_family == sa_family_t(AF_INET),
                  let inet = rawBuffer.baseAddress?.assumingMemoryBound(to: sockaddr_in.self) else {
                return nil
            }
            var address = inet.pointee.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                return nil
            }
            return String(cString: buffer)
        }
    }

    private func ipv6String(from data: Data) -> String? {
        data.withUnsafeBytes { rawBuffer in
            guard let sockaddr = rawBuffer.baseAddress?.assumingMemoryBound(to: sockaddr.self),
                  sockaddr.pointee.sa_family == sa_family_t(AF_INET6),
                  let inet = rawBuffer.baseAddress?.assumingMemoryBound(to: sockaddr_in6.self) else {
                return nil
            }
            var address = inet.pointee.sin6_addr
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else {
                return nil
            }
            return String(cString: buffer)
        }
    }
}
