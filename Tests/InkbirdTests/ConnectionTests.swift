//
//  ConnectionTests.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import XCTest
@testable import Inkbird
import Bluetooth
import GATT

/// End-to-end tests of ``InkbirdConnection`` against a simulated IBS-TH2.
final class ConnectionTests: XCTestCase {

    func testLiveReading() async throws {
        let central = TestCentral(device: { _ in [] })
        let connection = try await central.connect(to: central.peripheral, model: .ibsTH2)
        XCTAssertEqual(connection.model, .ibsTH2)
        let reading = try await connection.readLive()
        XCTAssertEqual(reading.temperature, 26.97, accuracy: 0.001)
        XCTAssertEqual(reading.humidity, 56.54, accuracy: 0.001)
        let settings = try await connection.readSettings()
        XCTAssertEqual(settings.interval, 120)
        let count = try await connection.readRecordCount()
        XCTAssertEqual(count, 289)
        XCTAssertTrue(central.writes.isEmpty)
        await connection.disconnect()
        XCTAssertFalse(central.isConnected)
        do {
            _ = try await connection.readLive()
            XCTFail()
        } catch InkbirdConnectionError.disconnected { }
    }

    func testHistory() async throws {
        // replays the Inkbird app's sync from the 2026-10-28 capture
        let temperature = try CapturedPacketTests.fixture("history-temperature")
        let humidity = try CapturedPacketTests.fixture("history-humidity")
        let central = TestCentral(device: Self.sensor(temperature: temperature, humidity: humidity))
        let connection = try await central.connect(to: central.peripheral, model: .ibsTH2)
        let start = Date()
        let history = try await connection.history(quietPeriod: 0.2)
        XCTAssertEqual(history.count, 6000)
        XCTAssertEqual(history.suffix(3).map { $0.temperature }, [24.47, 26.54, 26.96])
        XCTAssertEqual(history[5999].humidity, 56.29, accuracy: 0.001)
        // pairs 2 minutes apart, every 20 minutes, the newest in the last slot before the download
        XCTAssertEqual(Set(zip(history, history.dropFirst()).map { $1.date.timeIntervalSince($0.date) }), [120, 1080])
        XCTAssertLessThanOrEqual(history[5999].date, start)
        XCTAssertGreaterThan(history[5999].date, start.addingTimeInterval(-1080))
        // the same requests as the Inkbird app, and nothing written to the reset characteristic
        XCTAssertEqual(central.writes, [[0x02], [0x01], [0x07], [0x04], [0x03], [0x08]])
        XCTAssertEqual(Set(central.writtenCharacteristics), [.inkbirdHistoryRequest])
        await connection.disconnect()
    }

    func testPaddedHistory() async throws {
        // 6003 records, as the sensor sent on 2026-10-29: 601 notifications, the last padded with zeros
        let temperature = try CapturedPacketTests.fixture("history-temperature") + hex("97 0A A2 0A A4 0A")
        let humidity = try CapturedPacketTests.fixture("history-humidity") + hex("31 17 39 17 2D 17")
        let central = TestCentral(device: Self.sensor(temperature: temperature, humidity: humidity))
        let connection = try await central.connect(to: central.peripheral, model: .ibsTH2)
        let history = try await connection.history(quietPeriod: 0.2)
        XCTAssertEqual(history.count, 6003)
        XCTAssertEqual(history.suffix(4).map { $0.temperature }, [26.96, 27.11, 27.22, 27.24])
        XCTAssertEqual(history[6002].humidity, 59.33, accuracy: 0.001)
        await connection.disconnect()
    }

    func testPartialHistory() async throws {
        // a sensor with 500 records: the download ends when the records stop, and the CRC still matches
        let temperature = Array(try CapturedPacketTests.fixture("history-temperature").suffix(1000))
        let humidity = Array(try CapturedPacketTests.fixture("history-humidity").suffix(1000))
        let central = TestCentral(device: Self.sensor(temperature: temperature, humidity: humidity))
        let connection = try await central.connect(to: central.peripheral, model: .ibsTH2)
        let history = try await connection.history(timeout: 0.2, quietPeriod: 0.2)
        XCTAssertEqual(history.count, 500)
        XCTAssertEqual(history.last?.temperature, 26.96)
        await connection.disconnect()
    }

    func testChecksumMismatch() async throws {
        let temperature = try CapturedPacketTests.fixture("history-temperature")
        var sensor = Self.sensor(temperature: temperature, humidity: temperature)
        // one record corrupted in transit
        let original = sensor
        sensor = { request in
            var frames = original(request)
            if request == [0x01] {
                frames[100][0] ^= 0x01
            }
            return frames
        }
        let central = TestCentral(device: sensor)
        let connection = try await central.connect(to: central.peripheral, model: .ibsTH2)
        do {
            _ = try await connection.download(.temperature, quietPeriod: 0.2)
            XCTFail()
        } catch InkbirdConnectionError.checksumMismatch { }
        await connection.disconnect()
    }

    func testGapInRecords() async throws {
        // a weak connection pauses the records partway through
        let temperature = try CapturedPacketTests.fixture("history-temperature")
        let humidity = try CapturedPacketTests.fixture("history-humidity")
        let gap = TestCentral.Gap(request: .temperatureRecords, afterFrame: 300, duration: 0.5)
        let central = TestCentral(gap: gap, device: Self.sensor(temperature: temperature, humidity: humidity))
        let connection = try await central.connect(to: central.peripheral, model: .ibsTH2)
        let history = try await connection.history(quietPeriod: 1)
        XCTAssertEqual(history.count, 6000)
        XCTAssertEqual(history.suffix(3).map { $0.temperature }, [24.47, 26.54, 26.96])
        await connection.disconnect()
    }

    func testGapLongerThanQuietPeriod() async throws {
        // the records stop at the gap, so the checksum does not match
        let temperature = try CapturedPacketTests.fixture("history-temperature")
        let gap = TestCentral.Gap(request: .temperatureRecords, afterFrame: 300, duration: 0.5)
        let central = TestCentral(gap: gap, device: Self.sensor(temperature: temperature, humidity: temperature))
        let connection = try await central.connect(to: central.peripheral, model: .ibsTH2)
        do {
            _ = try await connection.download(.temperature, quietPeriod: 0.1)
            XCTFail()
        } catch InkbirdConnectionError.checksumMismatch { }
        await connection.disconnect()
    }

    func testHistoryTimeout() async throws {
        // the device accepts the request but never streams
        let central = TestCentral(device: { _ in [] })
        let connection = try await central.connect(to: central.peripheral, model: .ibsTH2)
        do {
            _ = try await connection.history(timeout: 0.2)
            XCTFail()
        } catch InkbirdConnectionError.timeout { }
        await connection.disconnect()
    }

    func testConnectTimeout() async throws {
        let central = TestCentral(isAdvertising: false, device: { _ in [] })
        do {
            _ = try await central.connect(to: central.peripheral, model: .ibsTH2, connectTimeout: 0.2)
            XCTFail()
        } catch InkbirdConnectionError.connectionTimeout { }
        XCTAssertTrue(central.writes.isEmpty)
    }

    func testCharacteristicNotFound() async throws {
        let central = TestCentral(services: [], device: { _ in [] })
        do {
            _ = try await central.connect(to: central.peripheral, model: .ibsTH2)
            XCTFail()
        } catch InkbirdConnectionError.characteristicNotFound(.inkbirdRealTimeData) { }
        XCTAssertFalse(central.isConnected)
    }

    func testDeviceDisconnect() async throws {
        let central = TestCentral(device: { _ in [] })
        let connection = try await central.connect(to: central.peripheral, model: .ibsTH2)
        _ = try await connection.readLive()
        central.dropConnection()
        for await _ in connection.events { }
        let isConnected = await connection.isConnected
        XCTAssertFalse(isConnected)
        do {
            _ = try await connection.readLive()
            XCTFail()
        } catch InkbirdConnectionError.disconnected { }
    }

    func testDisconnectDuringDownload() async throws {
        // the device sends the header, then drops the connection while the records are expected
        let central = TestCentral(device: { request in
            request == [0x02] ? [hex("30 75 00 00 1E FE 00 00 00 00 00 00 00 00 00 00 00 00 00 00")] : []
        })
        let connection = try await central.connect(to: central.peripheral, model: .ibsTH2)
        let download = Task { try await connection.history() }
        try await Task.sleep(nanoseconds: 100_000_000)
        central.dropConnection()
        do {
            _ = try await download.value
            XCTFail()
        } catch InkbirdConnectionError.disconnected { }
    }

    /// Simulated sensor: answers history requests on `FFF6` like the captured IBS-TH2.
    static func sensor(temperature: [UInt8], humidity: [UInt8]) -> @Sendable ([UInt8]) -> [[UInt8]] {
        let header = hex("30 75 00 00 1E FE 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        // the last notification is padded with zeros
        func frames(_ records: [UInt8]) -> [[UInt8]] {
            stride(from: 0, to: records.count, by: 20).map {
                let frame = Array(records[$0 ..< min($0 + 20, records.count)])
                return frame + [UInt8](repeating: 0, count: 20 - frame.count)
            }
        }
        func checksum(_ records: [UInt8]) -> [UInt8] {
            let crc = UInt16(crc16Modbus: records)
            return [UInt8(crc & 0xFF), UInt8(crc >> 8)] + [UInt8](repeating: 0, count: 18)
        }
        let replies: [InkbirdHistoryRequest: [[UInt8]]] = [
            .temperatureHeader: [header],
            .temperatureRecords: frames(temperature),
            .temperatureChecksum: [checksum(temperature)],
            .humidityHeader: [header],
            .humidityRecords: frames(humidity),
            .humidityChecksum: [checksum(humidity)],
        ]
        return { request in
            InkbirdHistoryRequest(rawValue: request.first ?? 0).flatMap { replies[$0] } ?? []
        }
    }
}

// MARK: - Test Central

/// Simulated central with one IBS-TH2, using the handles and values captured on 2026-10-28.
private final class TestCentral: CentralManager, @unchecked Sendable {

    typealias Peripheral = GATT.Peripheral

    typealias Advertisement = LowEnergyAdvertisingData

    typealias AttributeID = UInt16

    typealias Data = Foundation.Data

    var log: (@Sendable (String) -> ())?

    let peripheral = Peripheral(id: BluetoothAddress(rawValue: "49:22:08:15:04:CB")!)

    /// Device behavior: returns the `FFF6` notifications for each request written to `FFF8`.
    let device: @Sendable ([UInt8]) -> [[UInt8]]

    /// Services the device exposes.
    let services: [BluetoothUUID]

    /// Values returned by reads.
    let values: [BluetoothUUID: [UInt8]] = [
        .inkbirdSettings: hex("00 00 00 00 00 00 00 78 00 00 00 32 2D 33 AF 8C 00 00 00 00"),
        .inkbirdRealTimeData: hex("89 0A 16 16 00 15 A3"),
        .inkbirdRecordCount: hex("21 01 00 00"),
    ]

    /// Whether `connect(to:)` succeeds; otherwise it never returns, like CoreBluetooth.
    let isAdvertising: Bool

    /// Pause in the notifications replying to a request.
    struct Gap {
        let request: InkbirdHistoryRequest
        let afterFrame: Int
        let duration: TimeInterval
    }

    let gap: Gap?

    private let lock = NSLock()

    private var _writes = [(BluetoothUUID, [UInt8])]()

    private var _isConnected = false

    private var notify = [BluetoothUUID: AsyncIndefiniteStream<Data>.Continuation]()

    init(
        isAdvertising: Bool = true,
        services: [BluetoothUUID] = [.bit16(0x180A), .inkbirdThermostat],
        gap: Gap? = nil,
        device: @escaping @Sendable ([UInt8]) -> [[UInt8]]
    ) {
        self.isAdvertising = isAdvertising
        self.gap = gap
        self.services = services
        self.device = device
    }

    /// Simulates the device closing the connection.
    func dropConnection() {
        let notify = lock.withLock {
            _isConnected = false
            let notify = self.notify
            self.notify.removeAll()
            return notify
        }
        notify.values.forEach { $0.finish(throwing: CentralError.disconnected) }
    }

    var writes: [[UInt8]] {
        lock.withLock { _writes.map { $0.1 } }
    }

    var writtenCharacteristics: [BluetoothUUID] {
        lock.withLock { _writes.map { $0.0 } }
    }

    var isConnected: Bool {
        lock.withLock { _isConnected }
    }

    var peripherals: [Peripheral: Bool] {
        get async { [peripheral: isConnected] }
    }

    func scan(filterDuplicates: Bool) async throws -> AsyncCentralScan<TestCentral> {
        AsyncCentralScan { _ in }
    }

    func connect(to peripheral: Peripheral) async throws {
        guard isAdvertising else {
            try await Task.sleep(nanoseconds: .max)
            return
        }
        lock.withLock { _isConnected = true }
    }

    func disconnect(_ peripheral: Peripheral) async {
        lock.withLock {
            _isConnected = false
            notify.removeAll()
        }
    }

    func disconnectAll() async {
        await disconnect(peripheral)
    }

    func discoverServices(
        _ services: Set<BluetoothUUID>,
        for peripheral: Peripheral
    ) async throws -> [Service<Peripheral, AttributeID>] {
        self.services.enumerated().map { index, uuid in
            Service(id: UInt16(index), uuid: uuid, peripheral: peripheral)
        }
    }

    func discoverCharacteristics(
        _ characteristics: Set<BluetoothUUID>,
        for service: Service<Peripheral, AttributeID>
    ) async throws -> [Characteristic<Peripheral, AttributeID>] {
        switch service.uuid {
        case .inkbirdThermostat:
            return [
                Characteristic(id: 0x21, uuid: .inkbirdSettings, peripheral: peripheral, properties: [.read, .write]),
                Characteristic(id: 0x24, uuid: .inkbirdRealTimeData, peripheral: peripheral, properties: [.read]),
                Characteristic(id: 0x2D, uuid: .inkbirdRecordCount, peripheral: peripheral, properties: [.read]),
                Characteristic(id: 0x30, uuid: .inkbirdHistoryData, peripheral: peripheral, properties: [.notify]),
                Characteristic(id: 0x37, uuid: .inkbirdHistoryRequest, peripheral: peripheral, properties: [.read, .write]),
                Characteristic(id: 0x3A, uuid: .bit16(0xFFF9), peripheral: peripheral, properties: [.write]),
            ]
        default:
            return []
        }
    }

    func readValue(for characteristic: Characteristic<Peripheral, AttributeID>) async throws -> Data {
        Data(values[characteristic.uuid] ?? [])
    }

    func writeValue(
        _ data: Data,
        for characteristic: Characteristic<Peripheral, AttributeID>,
        withResponse: Bool
    ) async throws {
        let frame = [UInt8](data)
        let notify = lock.withLock {
            _writes.append((characteristic.uuid, frame))
            return self.notify
        }
        guard characteristic.uuid == .inkbirdHistoryRequest else {
            return
        }
        let replies = device(frame)
        guard let gap, frame == [gap.request.rawValue], gap.afterFrame < replies.count else {
            for reply in replies {
                notify[.inkbirdHistoryData]?.yield(Data(reply))
            }
            return
        }
        for reply in replies.prefix(gap.afterFrame) {
            notify[.inkbirdHistoryData]?.yield(Data(reply))
        }
        let rest = Array(replies.dropFirst(gap.afterFrame))
        Task {
            try? await Task.sleep(nanoseconds: UInt64(gap.duration * 1_000_000_000))
            for reply in rest {
                notify[.inkbirdHistoryData]?.yield(Data(reply))
            }
        }
    }

    func discoverDescriptors(for characteristic: Characteristic<Peripheral, AttributeID>) async throws -> [Descriptor<Peripheral, AttributeID>] {
        []
    }

    func readValue(for descriptor: Descriptor<Peripheral, AttributeID>) async throws -> Data {
        Data()
    }

    func writeValue(_ data: Data, for descriptor: Descriptor<Peripheral, AttributeID>) async throws { }

    func notify(for characteristic: Characteristic<Peripheral, AttributeID>) async throws -> AsyncCentralNotifications<TestCentral> {
        // replies are sent all at once, not ~30 ms apart like the sensor, so buffer a whole history buffer
        AsyncCentralNotifications(bufferSize: 1000, onTermination: { }) { continuation in
            self.lock.withLock { self.notify[characteristic.uuid] = continuation }
        }
    }

    func maximumTransmissionUnit(for peripheral: Peripheral) async throws -> MaximumTransmissionUnit {
        MaximumTransmissionUnit(rawValue: 23)!
    }

    func rssi(for peripheral: Peripheral) async throws -> RSSI {
        RSSI(rawValue: -53)!
    }
}

private func hex(_ string: String) -> [UInt8] {
    string.split(separator: " ").compactMap { UInt8($0, radix: 16) }
}
