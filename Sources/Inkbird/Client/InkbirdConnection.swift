//
//  InkbirdConnection.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import Bluetooth
import GATT

/// Inkbird GATT Connection
///
/// Reads the live value and downloads the stored history of a connected sensor. Requests are sent one at a time.
///
/// Create one with ``GATT/CentralManager/connect(to:model:connectTimeout:timeout:)``.
public actor InkbirdConnection<Central: CentralManager> where Central: Sendable, Central.AttributeID: Sendable {

    public typealias Peripheral = Central.Peripheral

    public typealias Characteristic = GATT.Characteristic<Central.Peripheral, Central.AttributeID>

    // MARK: - Properties

    /// Connected peripheral.
    public nonisolated let peripheral: Peripheral

    /// Device model.
    public nonisolated let model: InkbirdModel

    /// History notifications that arrive outside a request. Finishes when the connection closes.
    public nonisolated let events: AsyncStream<[UInt8]>

    /// Whether the connection is still open.
    public private(set) var isConnected = true

    private let central: Central

    private let eventsContinuation: AsyncStream<[UInt8]>.Continuation

    private var characteristics = [BluetoothUUID: Characteristic]()

    private var notifications = [AsyncCentralNotifications<Central>]()

    private var tasks = [Task<Void, Never>]()

    /// Notifications being collected for a history request.
    private var collector: Collector?

    private var requestCount: UInt64 = 0

    private var queue: Task<Void, Never>?

    // MARK: - Initialization

    internal init(
        central: Central,
        peripheral: Peripheral,
        model: InkbirdModel
    ) {
        self.central = central
        self.peripheral = peripheral
        self.model = model
        var continuation: AsyncStream<[UInt8]>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventsContinuation = continuation
    }

    // MARK: - Methods

    /// Reads the current temperature and humidity.
    public func readLive(timeout: TimeInterval = 5) async throws -> InkbirdReading {
        try await enqueue {
            let bytes = try await self.read(.inkbirdRealTimeData, timeout: timeout)
            guard let reading = InkbirdReading(bytes: bytes) else {
                throw InkbirdConnectionError.invalidData(.inkbirdRealTimeData)
            }
            return reading
        }
    }

    /// Reads the sensor's settings, including the logging interval.
    public func readSettings(timeout: TimeInterval = 5) async throws -> InkbirdSettings {
        try await enqueue {
            try await self.performReadSettings(timeout: timeout)
        }
    }

    /// Reads the record counter, which goes up by one with each record.
    public func readRecordCount(timeout: TimeInterval = 5) async throws -> UInt32 {
        try await enqueue {
            let bytes = try await self.read(.inkbirdRecordCount, timeout: timeout)
            guard bytes.count >= 4 else {
                throw InkbirdConnectionError.invalidData(.inkbirdRecordCount)
            }
            return UInt32(littleEndian: UInt32(bytes: (bytes[0], bytes[1], bytes[2], bytes[3])))
        }
    }

    /// Downloads the record bytes of one history buffer, oldest first, and checks them against the sensor's CRC.
    ///
    /// - Parameter timeout: Time allowed for each reply, and between records.
    public func download(
        _ buffer: InkbirdHistoryBuffer,
        timeout: TimeInterval = 5
    ) async throws -> [UInt8] {
        try await enqueue {
            try await self.performDownload(buffer, timeout: timeout)
        }
    }

    /// Downloads the stored history: about 6000 readings per buffer.
    ///
    /// A full download takes about 90 seconds.
    ///
    /// - Warning: Dates assume records are ``InkbirdSettings/interval`` apart, but a real sensor
    /// stored them about 8–9 minutes apart while sampling every 120 s. See `Docs/BLE-Protocol.md`.
    ///
    /// - Parameter timeout: Time allowed for each reply, and between records.
    public func history(timeout: TimeInterval = 5) async throws -> [InkbirdHistoryReading] {
        try await enqueue {
            let settings = try await self.performReadSettings(timeout: timeout)
            // the newest record is at most one interval old when the download starts
            let end = Date()
            let temperature = try await self.performDownload(.temperature, timeout: timeout)
            let humidity = try await self.performDownload(.humidity, timeout: timeout)
            return InkbirdHistoryReading.decode(
                temperature: temperature,
                humidity: humidity,
                end: end,
                interval: TimeInterval(settings.interval)
            )
        }
    }

    /// Closes the connection.
    public func disconnect() async {
        guard isConnected else {
            return
        }
        close()
        await central.disconnect(peripheral)
    }
}

// MARK: - Setup

internal extension InkbirdConnection {

    func setup() async throws {
        // discover
        let services = try await central.discoverServices([.inkbirdThermostat], for: peripheral)
        for service in services where service.uuid == .inkbirdThermostat {
            let characteristics = try await central.discoverCharacteristics([], for: service)
            for characteristic in characteristics {
                self.characteristics[characteristic.uuid] = characteristic
            }
        }
        for uuid in [BluetoothUUID.inkbirdRealTimeData, .inkbirdHistoryRequest, .inkbirdHistoryData] {
            guard characteristics[uuid] != nil else {
                throw InkbirdConnectionError.characteristicNotFound(uuid)
            }
        }
        // subscribe
        guard let history = characteristics[.inkbirdHistoryData] else {
            throw InkbirdConnectionError.characteristicNotFound(.inkbirdHistoryData)
        }
        try await subscribe(history)
    }
}

// MARK: - Private

private extension InkbirdConnection {

    struct Collector {

        let id: UInt64

        /// Notifications to wait for, or `nil` to collect until the device goes quiet.
        let count: Int?

        /// Time allowed after each notification.
        let quiet: TimeInterval

        /// The request ends if no notification arrives by then.
        var deadline: Date

        var frames = [[UInt8]]()

        let continuation: CheckedContinuation<[[UInt8]], Error>
    }

    /// Runs operations one at a time, in order.
    func enqueue<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = queue
        let task = Task<T, Error> {
            _ = await previous?.value
            return try await operation()
        }
        queue = Task { _ = await task.result }
        return try await task.value
    }

    func characteristic(_ uuid: BluetoothUUID) throws -> Characteristic {
        guard isConnected else {
            throw InkbirdConnectionError.disconnected
        }
        guard let characteristic = characteristics[uuid] else {
            throw InkbirdConnectionError.characteristicNotFound(uuid)
        }
        return characteristic
    }

    func read(_ uuid: BluetoothUUID, timeout: TimeInterval) async throws -> [UInt8] {
        let characteristic = try characteristic(uuid)
        let central = self.central
        let data = try await withTimeout(timeout) {
            try await central.readValue(for: characteristic)
        }
        return Array(data)
    }

    func performReadSettings(timeout: TimeInterval) async throws -> InkbirdSettings {
        let bytes = try await read(.inkbirdSettings, timeout: timeout)
        guard let settings = InkbirdSettings(bytes: bytes) else {
            throw InkbirdConnectionError.invalidData(.inkbirdSettings)
        }
        return settings
    }

    func performDownload(_ buffer: InkbirdHistoryBuffer, timeout: TimeInterval) async throws -> [UInt8] {
        // the Inkbird app requests the header first
        let header = try await collect(1, for: buffer.header, timeout: timeout)
        guard InkbirdHistoryReply.header(header[0]) != nil else {
            throw InkbirdConnectionError.invalidData(.inkbirdHistoryData)
        }
        // records arrive 10 to a notification, with no end marker
        let frames = try await collect(nil, for: buffer.records, timeout: timeout)
        let reply = try await collect(1, for: buffer.checksum, timeout: timeout)
        guard let checksum = InkbirdHistoryReply.checksum(reply[0]) else {
            throw InkbirdConnectionError.invalidData(.inkbirdHistoryData)
        }
        // the last notification is padded with zeros, which the checksum leaves out
        guard let records = InkbirdHistoryReply.records(Array(frames.joined()), checksum: checksum) else {
            throw InkbirdConnectionError.checksumMismatch
        }
        return records
    }

    /// Time without a notification after which a stream of records is complete.
    /// Records arrive about 30 ms apart; the longest gap seen was 0.21 s.
    static var quietPeriod: TimeInterval { 2 }

    /// Writes a history request and collects the notifications it causes.
    ///
    /// - Parameter count: Notifications to wait for, or `nil` to collect until the device goes quiet.
    func collect(
        _ count: Int?,
        for request: InkbirdHistoryRequest,
        timeout: TimeInterval
    ) async throws -> [[UInt8]] {
        let characteristic = try characteristic(.inkbirdHistoryRequest)
        requestCount += 1
        let id = requestCount
        let central = self.central
        return try await withCheckedThrowingContinuation { continuation in
            // notifications can arrive before the write returns
            collector = Collector(
                id: id,
                count: count,
                quiet: count == nil ? min(timeout, Self.quietPeriod) : timeout,
                deadline: Date().addingTimeInterval(timeout),
                continuation: continuation
            )
            Task {
                do {
                    try await central.writeValue(Central.Data([request.rawValue]), for: characteristic, withResponse: true)
                }
                catch {
                    self.finishCollector(id, .failure(error))
                }
            }
            Task {
                await self.watchCollector(id)
            }
        }
    }

    /// Ends the request when no notification arrives in time: the timeout before the first one,
    /// then the quiet period while collecting records.
    func watchCollector(_ id: UInt64) async {
        while let collector, collector.id == id {
            let remaining = collector.deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                break
            }
            // notifications move the deadline, so check again well before it
            let wait = min(remaining, collector.quiet / 4)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        guard let collector, collector.id == id else {
            return
        }
        if collector.count == nil {
            finishCollector(id, .success(collector.frames)) // an empty buffer may send nothing
        } else {
            finishCollector(id, .failure(InkbirdConnectionError.timeout))
        }
    }

    func finishCollector(_ id: UInt64, _ result: Result<[[UInt8]], Error>) {
        guard let collector, collector.id == id else {
            return
        }
        self.collector = nil
        collector.continuation.resume(with: result)
    }

    func subscribe(_ characteristic: Characteristic) async throws {
        let stream = try await central.notify(for: characteristic)
        notifications.append(stream)
        let task = Task { [weak self] in
            do {
                for try await data in stream {
                    await self?.receive(Array(data))
                }
            }
            catch { }
            // the stream ends when the device disconnects
            await self?.connectionLost()
        }
        tasks.append(task)
    }

    func receive(_ bytes: [UInt8]) {
        guard var collector else {
            eventsContinuation.yield(bytes)
            return
        }
        collector.frames.append(bytes)
        collector.deadline = Date().addingTimeInterval(collector.quiet)
        self.collector = collector
        if let count = collector.count, collector.frames.count >= count {
            finishCollector(collector.id, .success(collector.frames))
        }
    }

    /// Called when the device closed the connection.
    func connectionLost() {
        guard isConnected else {
            return
        }
        close()
    }

    func close() {
        isConnected = false
        notifications.forEach { $0.stop() }
        tasks.forEach { $0.cancel() }
        if let collector {
            finishCollector(collector.id, .failure(InkbirdConnectionError.disconnected))
        }
        eventsContinuation.finish()
    }
}

// MARK: - CentralManager

public extension CentralManager where Self: Sendable, AttributeID: Sendable {

    /// Connects to an Inkbird sensor and discovers its characteristics.
    ///
    /// - Parameter connectTimeout: Time allowed to establish the Bluetooth connection.
    /// - Parameter timeout: Time allowed for each reply during setup.
    func connect(
        to peripheral: Peripheral,
        model: InkbirdModel,
        connectTimeout: TimeInterval = 15,
        timeout: TimeInterval = 5
    ) async throws -> InkbirdConnection<Self> {
        // CoreBluetooth waits forever for a device that is not advertising
        do {
            try await withTimeout(connectTimeout) {
                try await self.connect(to: peripheral)
            } late: { result in
                if case .success = result {
                    await self.disconnect(peripheral)
                }
            }
        }
        catch InkbirdConnectionError.timeout {
            throw InkbirdConnectionError.connectionTimeout
        }
        let connection = InkbirdConnection(
            central: self,
            peripheral: peripheral,
            model: model
        )
        do {
            try await withTimeout(timeout) {
                try await connection.setup()
            }
        }
        catch {
            await connection.disconnect()
            throw error
        }
        return connection
    }
}

// MARK: - Timeout

/// Runs the operation, throwing ``InkbirdConnectionError/timeout`` if it does not finish in time.
///
/// The operation keeps running after a timeout; `late` receives its result.
internal func withTimeout<T: Sendable>(
    _ timeout: TimeInterval,
    operation: @escaping @Sendable () async throws -> T,
    late: @escaping @Sendable (Result<T, Error>) async -> () = { _ in }
) async throws -> T {
    let result = TimeoutResult<T>()
    return try await withCheckedThrowingContinuation { continuation in
        result.continuation = continuation
        let task = Task {
            let value: Result<T, Error>
            do { value = .success(try await operation()) }
            catch { value = .failure(error) }
            if result.resume(with: value) == false {
                await late(value)
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if result.resume(with: .failure(InkbirdConnectionError.timeout)) {
                task.cancel()
            }
        }
    }
}

/// Resumes a continuation once.
private final class TimeoutResult<T: Sendable>: @unchecked Sendable {

    private let lock = NSLock()

    private var _continuation: CheckedContinuation<T, Error>?

    var continuation: CheckedContinuation<T, Error>? {
        get { lock.withLock { _continuation } }
        set { lock.withLock { _continuation = newValue } }
    }

    /// Returns `false` if already resumed.
    func resume(with result: Result<T, Error>) -> Bool {
        let continuation = lock.withLock {
            let continuation = _continuation
            _continuation = nil
            return continuation
        }
        guard let continuation else {
            return false
        }
        continuation.resume(with: result)
        return true
    }
}

// MARK: - Error

/// Inkbird connection error.
public enum InkbirdConnectionError: Error, Equatable, Sendable {

    /// No reply within the timeout.
    case timeout

    /// The Bluetooth connection was not established in time, usually because the device is out of range
    /// or connected to another phone.
    case connectionTimeout

    /// The connection was closed.
    case disconnected

    /// A required characteristic was not found.
    case characteristicNotFound(BluetoothUUID)

    /// A characteristic held a value that could not be decoded.
    case invalidData(BluetoothUUID)

    /// The downloaded history did not match the sensor's checksum.
    case checksumMismatch
}

extension InkbirdConnectionError: CustomStringConvertible {

    public var description: String {
        switch self {
        case .timeout:
            return "No reply from the device"
        case .connectionTimeout:
            return "Could not connect; the device may be out of range or connected to another phone"
        case .disconnected:
            return "The device disconnected"
        case let .characteristicNotFound(uuid):
            return "Characteristic \(uuid) not found"
        case let .invalidData(uuid):
            return "Invalid data from characteristic \(uuid)"
        case .checksumMismatch:
            return "The downloaded history was incomplete or corrupted"
        }
    }
}
