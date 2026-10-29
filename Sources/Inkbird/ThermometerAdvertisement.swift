//
//  ThermometerAdvertisement.swift
//  
//
//  Created by Alsey Coleman Miller on 3/15/23.
//

import Foundation
import Bluetooth
import GATT

public extension InkbirdAdvertisement {
    
    struct Thermometer: Equatable, Hashable {
        
        public static var services: [BluetoothUUID] { [.inkbirdThermostat] }
        
        public let manufacturingData: ManufacturingData
        
        public let name: Name
    }
}

public extension InkbirdAdvertisement.Thermometer {
    
    enum Name: String, Codable, CaseIterable {
        
        case sps
        case tps
    }
}

public extension InkbirdAdvertisement.Thermometer {
    
    init?<T: GATT.AdvertisementData>(_ advertisementData: T) {
        guard let manufacturingData = advertisementData.manufacturerData.flatMap({ ManufacturingData($0) }),
              let name = advertisementData.localName.flatMap({ Name(rawValue: $0) })
            else { return nil }
        self.manufacturingData = manufacturingData
        self.name = name
    }
}

public extension InkbirdAdvertisement.Thermometer {
    
    /// Reading broadcast in the manufacturer specific data.
    ///
    /// See `Docs/BLE-Protocol.md` for the byte layout.
    struct ManufacturingData: Equatable, Hashable {

        public var temperature: Temperature

        public var humidity: Humidity

        public var probe: Probe

        public var batteryLevel: BatteryLevel
    }
}

public extension InkbirdAdvertisement.Thermometer.ManufacturingData {

    /// Length of the manufacturer specific data, including the two bytes reported as the company identifier.
    static var length: Int { 9 }

    /// Decodes the manufacturer specific data.
    ///
    /// - Parameter bytes: All 9 bytes. The first two are the temperature,
    /// which platforms report as the company identifier.
    /// - Returns: `nil` if the length or CRC is invalid.
    init?(bytes: [UInt8]) {
        guard bytes.count == Self.length else {
            return nil
        }
        let crc = UInt16(littleEndian: UInt16(bytes: (bytes[5], bytes[6])))
        guard UInt16(crc16Modbus: bytes[0 ..< 5]) == crc,
              let batteryLevel = BatteryLevel(rawValue: bytes[7]) else {
            return nil
        }
        self.temperature = Temperature(rawValue: Int16(bitPattern: UInt16(littleEndian: UInt16(bytes: (bytes[0], bytes[1])))))
        self.humidity = Humidity(rawValue: UInt16(littleEndian: UInt16(bytes: (bytes[2], bytes[3]))))
        self.probe = Probe(rawValue: bytes[4])
        self.batteryLevel = batteryLevel
    }
}

internal extension InkbirdAdvertisement.Thermometer.ManufacturingData {

    init?<T: DataContainer>(_ manufacturerSpecificData: GATT.ManufacturerSpecificData<T>) {
        // the sensor has no company identifier, so put back the first two bytes
        let companyIdentifier = manufacturerSpecificData.companyIdentifier.rawValue.littleEndian.bytes
        let bytes = [companyIdentifier.0, companyIdentifier.1] + Array(manufacturerSpecificData.additionalData)
        self.init(bytes: bytes)
    }
}

public extension InkbirdAdvertisement.Thermometer.ManufacturingData {

    struct Temperature: RawRepresentable, Equatable, Hashable, Codable {

        public let rawValue: Int16

        public init(rawValue: Int16) {
            self.rawValue = rawValue
        }
    }
}

extension InkbirdAdvertisement.Thermometer.ManufacturingData.Temperature: CustomStringConvertible {
    
    public var description: String {
        return "\(celcius) C°"
    }
}

public extension InkbirdAdvertisement.Thermometer.ManufacturingData.Temperature {
    
    var celcius: Float {
        Float(rawValue) / 100
    }
}

public extension InkbirdAdvertisement.Thermometer.ManufacturingData {
    
    struct Humidity: RawRepresentable, Equatable, Hashable, Codable {
        
        public let rawValue: UInt16
        
        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }
    }
}

extension InkbirdAdvertisement.Thermometer.ManufacturingData.Humidity: CustomStringConvertible {
    
    public var description: String {
        return "\(percentage) %"
    }
}

public extension InkbirdAdvertisement.Thermometer.ManufacturingData.Humidity {
    
    var percentage: Float {
        Float(rawValue) / 100
    }
}

public extension InkbirdAdvertisement.Thermometer.ManufacturingData {

    /// Sensor that took the reading.
    struct Probe: RawRepresentable, Equatable, Hashable, Codable {

        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
    }
}

public extension InkbirdAdvertisement.Thermometer.ManufacturingData.Probe {

    /// Sensor inside the device.
    static var builtIn: InkbirdAdvertisement.Thermometer.ManufacturingData.Probe { .init(rawValue: 0x00) }

    /// External probe on a cable.
    static var external: InkbirdAdvertisement.Thermometer.ManufacturingData.Probe { .init(rawValue: 0x01) }
}

extension InkbirdAdvertisement.Thermometer.ManufacturingData.Probe: CustomStringConvertible {

    public var description: String {
        switch self {
        case .builtIn:
            return "Built-in"
        case .external:
            return "External"
        default:
            return "Unknown (\(rawValue))"
        }
    }
}

public extension InkbirdAdvertisement.Thermometer.ManufacturingData {

    struct BatteryLevel: RawRepresentable, Equatable, Hashable, Codable {
                
        public let rawValue: UInt8
        
        public init?(rawValue: UInt8) {
            guard rawValue <= Self.max.rawValue else {
                return nil
            }
            self.init(rawValue)
        }
        
        private init(_ raw: UInt8) {
            self.rawValue = raw
        }
    }
}

public extension InkbirdAdvertisement.Thermometer.ManufacturingData.BatteryLevel {
    
    static var min: InkbirdAdvertisement.Thermometer.ManufacturingData.BatteryLevel { .init(0) }
    
    static var max: InkbirdAdvertisement.Thermometer.ManufacturingData.BatteryLevel { .init(100) }
}

extension InkbirdAdvertisement.Thermometer.ManufacturingData.BatteryLevel: CustomStringConvertible {
    
    public var description: String {
        return "\(rawValue) %"
    }
}

extension InkbirdAdvertisement.Thermometer.ManufacturingData.BatteryLevel: ExpressibleByIntegerLiteral {
    
    public init(integerLiteral value: UInt8) {
        self.init(Swift.min(value, Self.max.rawValue))
    }
}
