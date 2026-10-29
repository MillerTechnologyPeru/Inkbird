//
//  ThermometerProtocol.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation

// See `Docs/BLE-Protocol.md` sections 3 and 4.

/// Live reading from the `Real time data` characteristic (`FFF2`).
public struct InkbirdReading: Equatable, Hashable, Sendable {

    public typealias Probe = InkbirdAdvertisement.Thermometer.ManufacturingData.Probe

    /// Temperature in degrees Celsius.
    public let temperature: Float

    /// Relative humidity in percent.
    public let humidity: Float

    /// Sensor that took the reading.
    public let probe: Probe
}

public extension InkbirdReading {

    /// Decodes the 7-byte value: temperature, humidity, probe and CRC.
    ///
    /// - Returns: `nil` if the length or CRC is invalid.
    init?(bytes: [UInt8]) {
        guard bytes.count == 7,
              UInt16(crc16Modbus: bytes[0 ..< 5]) == UInt16(littleEndian: UInt16(bytes: (bytes[5], bytes[6]))) else {
            return nil
        }
        let temperature = Int16(bitPattern: UInt16(littleEndian: UInt16(bytes: (bytes[0], bytes[1]))))
        let humidity = UInt16(littleEndian: UInt16(bytes: (bytes[2], bytes[3])))
        self.temperature = Float(temperature) / 100
        self.humidity = Float(humidity) / 100
        self.probe = Probe(rawValue: bytes[4])
    }
}

/// Settings from the `cfg data` characteristic (`FFF1`).
public struct InkbirdSettings: Equatable, Hashable, Sendable {

    /// Time between history records, in seconds.
    ///
    /// Read from bytes 7–8. Only `120` has been seen, so whether the field is one or two bytes is unconfirmed.
    public let interval: UInt16

    /// The 20-byte value, for fields not decoded yet.
    public let bytes: [UInt8]
}

public extension InkbirdSettings {

    /// Decodes the 20-byte value. Bytes 14–15 are a CRC of bytes 0–13.
    ///
    /// - Returns: `nil` if the length or CRC is invalid.
    init?(bytes: [UInt8]) {
        guard bytes.count == 20,
              UInt16(crc16Modbus: bytes[0 ..< 14]) == UInt16(littleEndian: UInt16(bytes: (bytes[14], bytes[15]))) else {
            return nil
        }
        self.interval = UInt16(littleEndian: UInt16(bytes: (bytes[7], bytes[8])))
        self.bytes = bytes
    }
}

/// Byte written to the `his data type` characteristic (`FFF8`). The reply arrives on `history data` (`FFF6`).
public enum InkbirdHistoryRequest: UInt8, CaseIterable, Sendable {

    /// Temperature records.
    case temperatureRecords = 0x01

    /// Temperature header.
    case temperatureHeader = 0x02

    /// Humidity records.
    case humidityRecords = 0x03

    /// Humidity header.
    case humidityHeader = 0x04

    /// CRC of the temperature records.
    case temperatureChecksum = 0x07

    /// CRC of the humidity records.
    case humidityChecksum = 0x08
}

/// History buffer kept by the sensor.
public enum InkbirdHistoryBuffer: CaseIterable, Sendable {

    case temperature
    case humidity
}

public extension InkbirdHistoryBuffer {

    /// Records each buffer holds. The Inkbird app stops reading at this count.
    static var capacity: Int { 6000 }

    /// Size of a record in bytes.
    static var recordSize: Int { 2 }

    var header: InkbirdHistoryRequest {
        switch self {
        case .temperature: return .temperatureHeader
        case .humidity: return .humidityHeader
        }
    }

    var records: InkbirdHistoryRequest {
        switch self {
        case .temperature: return .temperatureRecords
        case .humidity: return .humidityRecords
        }
    }

    var checksum: InkbirdHistoryRequest {
        switch self {
        case .temperature: return .temperatureChecksum
        case .humidity: return .humidityChecksum
        }
    }
}

/// Reply to a header or checksum request: a little endian value followed by zeros.
internal enum InkbirdHistoryReply {

    /// Decodes a header: a 4-byte value and its CRC. Meaning unknown; `30000` on the captured sensor.
    static func header(_ bytes: [UInt8]) -> UInt32? {
        guard bytes.count >= 6,
              UInt16(crc16Modbus: bytes[0 ..< 4]) == UInt16(littleEndian: UInt16(bytes: (bytes[4], bytes[5]))) else {
            return nil
        }
        return UInt32(littleEndian: UInt32(bytes: (bytes[0], bytes[1], bytes[2], bytes[3])))
    }

    /// Decodes a checksum reply: the CRC of all record bytes.
    static func checksum(_ bytes: [UInt8]) -> UInt16? {
        guard bytes.count >= 2 else {
            return nil
        }
        return UInt16(littleEndian: UInt16(bytes: (bytes[0], bytes[1])))
    }
}

/// Reading from the sensor's history.
public struct InkbirdHistoryReading: Equatable, Hashable, Sendable {

    /// Estimated time of the reading. Records carry no timestamp, so this is derived from the download time
    /// and the logging interval, and can be up to one interval late.
    public let date: Date

    /// Temperature in degrees Celsius.
    public let temperature: Float

    /// Relative humidity in percent.
    public let humidity: Float
}

public extension InkbirdHistoryReading {

    /// Combines the record bytes of both buffers, oldest first.
    ///
    /// - Parameter end: Date of the newest record, usually the time of the download.
    /// - Parameter interval: Time between records.
    static func decode(
        temperature: [UInt8],
        humidity: [UInt8],
        end: Date,
        interval: TimeInterval
    ) -> [InkbirdHistoryReading] {
        let temperatures = stride(from: 0, to: temperature.count - 1, by: 2).map {
            Int16(bitPattern: UInt16(littleEndian: UInt16(bytes: (temperature[$0], temperature[$0 + 1]))))
        }
        let humidities = stride(from: 0, to: humidity.count - 1, by: 2).map {
            UInt16(littleEndian: UInt16(bytes: (humidity[$0], humidity[$0 + 1])))
        }
        // both buffers end with the newest record
        let count = min(temperatures.count, humidities.count)
        return zip(temperatures.suffix(count), humidities.suffix(count)).enumerated().map { index, record in
            InkbirdHistoryReading(
                date: end.addingTimeInterval(-Double(count - 1 - index) * interval),
                temperature: Float(record.0) / 100,
                humidity: Float(record.1) / 100
            )
        }
    }
}
