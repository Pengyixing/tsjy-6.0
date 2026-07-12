import XCTest
import Network
@testable import tsjy

final class ModbusTCPServerTests: XCTestCase {
    
    var server: ModbusTCPServer!
    
    override func setUp() {
        super.setUp()
        // 假设我们分配 100 个寄存器，默认值全为 0
        server = ModbusTCPServer(port: 5020, registerCount: 100)
    }
    
    override func tearDown() {
        server.stop()
        server = nil
        super.tearDown()
    }
    
    func testReadHoldingRegisters_FunctionCode03() {
        // 先在服务器内存里预设几个值
        server.setRegister(address: 0, value: 55)
        server.setRegister(address: 1, value: 40)
        
        // 构造一个标准的 Modbus TCP 请求: 读保持寄存器 (FC=03), 从地址 0 开始，读 2 个
        let requestBytes: [UInt8] = [
            0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x01,
            0x03, 0x00, 0x00, 0x00, 0x02
        ]
        
        guard let responseData = server.handleModbusRequest(data: Data(requestBytes)) else {
            XCTFail("Server should return a response")
            return
        }
        
        let responseBytes = [UInt8](responseData)
        
        // 期望的响应报文:
        let expectedBytes: [UInt8] = [
            0x00, 0x01, 0x00, 0x00, 0x00, 0x07, 0x01,
            0x03, 0x04, 0x00, 0x37, 0x00, 0x28
        ]
        
        XCTAssertEqual(responseBytes, expectedBytes, "Response bytes do not match expected Modbus TCP format")
    }
    
    func testWriteSingleRegister_FunctionCode06() {
        // 构造一个写单寄存器的请求 (FC=06), 写地址 2, 值为 88 (0x0058)
        let requestBytes: [UInt8] = [
            0x00, 0x02, 0x00, 0x00, 0x00, 0x06, 0x01,
            0x06, 0x00, 0x02, 0x00, 0x58
        ]
        
        let _ = server.handleModbusRequest(data: Data(requestBytes))
        
        // 验证服务器内部的内存数组是否被正确修改
        let value = server.getRegister(address: 2)
        XCTAssertEqual(value, 88, "Server memory was not updated correctly by Write Single Register command")
    }

    func testWriteSingleRegister_EmitsDiagnosticLog() {
        var messages: [String] = []
        server.onDiagnosticLog = { messages.append($0) }

        let requestBytes: [UInt8] = [
            0x00, 0x02, 0x00, 0x00, 0x00, 0x06, 0x01,
            0x06, 0x00, 0x02, 0x00, 0x58
        ]

        _ = server.handleModbusRequest(data: Data(requestBytes))

        XCTAssertTrue(messages.contains(where: { $0.contains("FC6") && $0.contains("2=88") }))
    }

    func testAbsoluteFC6Address() {
        let localServer = ModbusTCPServer(port: 5021, registerCount: 200)
        defer { localServer.stop() }

        let requestBytes: [UInt8] = [
            0x00, 0x05, 0x00, 0x00, 0x00, 0x06, 0x01,
            0x06, 0x9C, 0xA5, 0x00, 0x09
        ]

        let response = localServer.handleModbusRequest(data: Data(requestBytes))

        XCTAssertNotNil(response)
        XCTAssertEqual(localServer.getRegister(address: 100), 9, "Absolute 4x address 40101 should map to local register 100")
    }

    func testAbsoluteFC16AddressRange() {
        let localServer = ModbusTCPServer(port: 5022, registerCount: 200)
        defer { localServer.stop() }

        let requestBytes: [UInt8] = [
            0x00, 0x06, 0x00, 0x00, 0x00, 0x11, 0x01,
            0x10, 0x9C, 0xA5, 0x00, 0x05, 0x0A,
            0x00, 0x09, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00
        ]

        let response = localServer.handleModbusRequest(data: Data(requestBytes))

        XCTAssertNotNil(response)
        XCTAssertEqual(localServer.getRegister(address: 100), 9)
        XCTAssertEqual(localServer.getRegister(address: 101), 1)
        XCTAssertEqual(localServer.getRegister(address: 102), 1)
        XCTAssertEqual(localServer.getRegister(address: 103), 0)
        XCTAssertEqual(localServer.getRegister(address: 104), 0)
    }

    func testAbsoluteFC16Address_ResponseEchoesOriginalAddress() {
        let localServer = ModbusTCPServer(port: 5023, registerCount: 200)
        defer { localServer.stop() }

        let requestBytes: [UInt8] = [
            0x00, 0x07, 0x00, 0x00, 0x00, 0x11, 0x01,
            0x10, 0x9C, 0xA5, 0x00, 0x05, 0x0A,
            0x00, 0x09, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00
        ]

        guard let response = localServer.handleModbusRequest(data: Data(requestBytes)) else {
            XCTFail("Server should return FC16 response")
            return
        }

        let responseBytes = [UInt8](response)
        XCTAssertEqual(Array(responseBytes[8...11]), [0x9C, 0xA5, 0x00, 0x05], "FC16 response should echo original absolute address and quantity")
    }

    func testInvalidFC6Address_ReturnsExceptionResponse() {
        let localServer = ModbusTCPServer(port: 5024, registerCount: 200)
        defer { localServer.stop() }

        let requestBytes: [UInt8] = [
            0x00, 0x08, 0x00, 0x00, 0x00, 0x06, 0x01,
            0x06, 0x01, 0x2C, 0x00, 0x01
        ]

        guard let response = localServer.handleModbusRequest(data: Data(requestBytes)) else {
            XCTFail("Server should return Modbus exception response")
            return
        }

        XCTAssertEqual([UInt8](response), [
            0x00, 0x08, 0x00, 0x00, 0x00, 0x03, 0x01,
            0x86, 0x02
        ])
    }

    func testReadWriteMultipleRegisters_FunctionCode23_ReadsAndWritesHoldingRegisters() {
        let localServer = ModbusTCPServer(port: 5025, registerCount: 200)
        defer { localServer.stop() }
        localServer.setRegister(address: 10, value: 0x1234)
        localServer.setRegister(address: 11, value: 0x5678)

        let requestBytes: [UInt8] = [
            0x00, 0x09, 0x00, 0x00, 0x00, 0x0F, 0x01,
            0x17,
            0x00, 0x0A, 0x00, 0x02,
            0x9C, 0xA5, 0x00, 0x01,
            0x02,
            0x00, 0x2A
        ]

        guard let response = localServer.handleModbusRequest(data: Data(requestBytes)) else {
            XCTFail("Server should return FC23 response")
            return
        }

        XCTAssertEqual([UInt8](response), [
            0x00, 0x09, 0x00, 0x00, 0x00, 0x07, 0x01,
            0x17, 0x04, 0x12, 0x34, 0x56, 0x78
        ])
        XCTAssertEqual(localServer.getRegister(address: 100), 42)
    }

    func testReadHoldingRegisters_DoesNotDeadlockOnServerQueue() throws {
        server.setRegister(address: 10, value: 123)

        let requestBytes: [UInt8] = [
            0x00, 0x03, 0x00, 0x00, 0x00, 0x06, 0x01,
            0x03, 0x00, 0x0A, 0x00, 0x01
        ]

        let expectation = expectation(description: "read request returns on server queue")

        server.executeOnServerQueue {
            let response = self.server.handleModbusRequest(data: Data(requestBytes))
            XCTAssertNotNil(response)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testWriteSingleRegister_DoesNotDeadlockOnServerQueue() throws {
        let requestBytes: [UInt8] = [
            0x00, 0x04, 0x00, 0x00, 0x00, 0x06, 0x01,
            0x06, 0x00, 0x05, 0x00, 0x66
        ]

        let expectation = expectation(description: "write request returns on server queue")

        server.executeOnServerQueue {
            let response = self.server.handleModbusRequest(data: Data(requestBytes))
            XCTAssertNotNil(response)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(server.getRegister(address: 5), 102)
    }

    func testFrameBuffer_WaitsUntil完整FC16报文到齐() {
        var buffer = ModbusTCPFrameBuffer()
        let frame = Data([
            0x00, 0x10, 0x00, 0x00, 0x00, 0x11, 0x01,
            0x10, 0x00, 0x64, 0x00, 0x05, 0x0A,
            0x00, 0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x04, 0x00, 0x05
        ])

        let firstHalf = frame.prefix(8)
        let secondHalf = frame.dropFirst(8)

        buffer.append(Data(firstHalf))
        XCTAssertNil(buffer.popNextFrame())

        buffer.append(Data(secondHalf))
        XCTAssertEqual(buffer.popNextFrame(), frame)
    }

    func testFrameBuffer_Can连续取出两个完整报文() {
        var buffer = ModbusTCPFrameBuffer()
        let frame1 = Data([
            0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x01,
            0x03, 0x00, 0x0A, 0x00, 0x01
        ])
        let frame2 = Data([
            0x00, 0x02, 0x00, 0x00, 0x00, 0x06, 0x01,
            0x06, 0x00, 0x64, 0x00, 0x01
        ])

        buffer.append(frame1 + frame2)

        XCTAssertEqual(buffer.popNextFrame(), frame1)
        XCTAssertEqual(buffer.popNextFrame(), frame2)
        XCTAssertNil(buffer.popNextFrame())
    }
}
