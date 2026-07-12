import Foundation

final class DiscoveryPublisher: NSObject {
    private var service: NetService?

    func start(name: String, serviceType: String, controlPort: UInt16, videoPort: UInt16) {
        stop()
        let service = NetService(domain: "local.", type: serviceType, name: name, port: Int32(controlPort))
        let txt: [String: Data] = [
            "videoPort": String(videoPort).data(using: .utf8) ?? Data(),
            "controlPort": String(controlPort).data(using: .utf8) ?? Data(),
            "gatewayName": name.data(using: .utf8) ?? Data()
        ]
        service.setTXTRecord(NetService.data(fromTXTRecord: txt))
        service.publish()
        self.service = service
    }

    func stop() {
        service?.stop()
        service = nil
    }
}
