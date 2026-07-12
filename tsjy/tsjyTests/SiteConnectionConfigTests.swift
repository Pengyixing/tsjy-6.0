import Testing
@testable import tsjy

struct SiteConnectionConfigTests {

    @Test func defaultModbusEndpoint_uses本地服务端5020监听地址() async throws {
        #expect(SiteConnectionConfig.defaultModbusEndpoint == "modbus://0.0.0.0:5020")
    }

    @Test func resolveConnectPLCURL_prefersExplicitReason() async throws {
        let resolved = SiteConnectionConfig.resolveConnectPLCURL(
            explicitURL: "modbus://10.0.0.5:1502",
            siteEndpointText: "modbus://0.0.0.0:5020"
        )

        #expect(resolved == "modbus://10.0.0.5:1502")
    }

    @Test func resolveConnectPLCURL_usesSiteEndpointInsteadOfLocalhostFallback() async throws {
        let resolved = SiteConnectionConfig.resolveConnectPLCURL(
            explicitURL: nil,
            siteEndpointText: "modbus://0.0.0.0:5020"
        )

        #expect(resolved == "modbus://0.0.0.0:5020")
    }

    @Test func modbusServerListeningMessage_contains等待PLC提示() async throws {
        let message = SiteConnectionConfig.modbusServerListeningMessage(
            port: 5020,
        )

        #expect(message.contains("5020"))
        #expect(message.contains("等待 PLC"))
    }

    @MainActor
    @Test func controlRegisterMap_matches最新拼装机点表() async throws {
        let bridge = SiteControlBridge()
        let map = bridge.debugControlRegisterMap()

        #expect(map["pumpStartCmd"] == 10)
        #expect(map["pumpStopCmd"] == 11)
        #expect(map["travelEnable"] == 12)
        #expect(map["cylinderEnable"] == 13)
        #expect(map["travelDirectionAN1"] == 14)
        #expect(map["rotationDirectionAN2"] == 15)
    }
}
