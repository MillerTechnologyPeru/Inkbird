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
    
    struct ManufacturingData: Equatable, Hashable {
        
        public var temperature: Temperature
        
        public var humidity: Humidity
        
        public var batteryLevel: BatteryLevel
    }
}

internal extension InkbirdAdvertisement.Thermometer.ManufacturingData {
    
    init?(_ manufacturerSpecificData: GATT.ManufacturerSpecificData) {
        guard manufacturerSpecificData.additionalData.count == 7
            else {
            return nil
        }
        let data = manufacturerSpecificData.additionalData
        guard let batteryLevel = BatteryLevel(rawValue: data[5]) else {
            return nil
        }
        self.temperature = Temperature(rawValue: manufacturerSpecificData.companyIdentifier.rawValue)
        self.humidity = Humidity(rawValue: UInt16(littleEndian: UInt16(bytes: (data[0], data[1]))))
        self.batteryLevel = batteryLevel
    }
}

public extension InkbirdAdvertisement.Thermometer.ManufacturingData {
    
    struct Temperature: RawRepresentable, Equatable, Hashable, Codable {
        
        public let rawValue: UInt16
        
        public init(rawValue: UInt16) {
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
