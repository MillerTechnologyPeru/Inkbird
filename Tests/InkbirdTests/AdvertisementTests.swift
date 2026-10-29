//
//  AdvertisementTests.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import XCTest
@testable import Inkbird
import Bluetooth
import GATT
import BluetoothGAP

final class AdvertisementTests: XCTestCase {

    typealias ManufacturingData = InkbirdAdvertisement.Thermometer.ManufacturingData

    /// IBS-TH2 `49:22:08:15:04:CB`, scanned with CoreBluetooth on 2026-10-28 while being warmed by hand.
    /// Expected values were checked against the bytes and the CRC of each payload.
    func testCapturedPayloads() throws {
        let samples: [(String, Int16, UInt16)] = [
            ("7C 09 FD 17 00 E8 56 64 08", 2428, 6141),
            ("84 0A 0E 16 00 B8 65 64 08", 2692, 5646),
            ("88 0A 13 16 00 38 62 64 08", 2696, 5651),
            ("8A 0A FF 15 00 80 A7 64 08", 2698, 5631),
            ("7E 0A FE 15 00 60 B2 64 08", 2686, 5630),
        ]
        for (payload, temperature, humidity) in samples {
            let reading = try XCTUnwrap(ManufacturingData(bytes: hex(payload)), payload)
            XCTAssertEqual(reading.temperature.rawValue, temperature, payload)
            XCTAssertEqual(reading.humidity.rawValue, humidity, payload)
            XCTAssertEqual(reading.probe, .builtIn, payload)
            XCTAssertEqual(reading.batteryLevel, 100, payload)
        }
        let reading = try XCTUnwrap(ManufacturingData(bytes: hex(samples[0].0)))
        XCTAssertEqual(reading.temperature.celcius, 24.28)
        XCTAssertEqual(reading.humidity.percentage, 61.41)
    }

    /// CoreBluetooth reports the first two bytes as the company identifier.
    func testCompanyIdentifierBytes() throws {
        let manufacturerData = GATT.ManufacturerSpecificData<Data>(
            companyIdentifier: 0x097C,
            additionalData: Data(hex("FD 17 00 E8 56 64 08"))
        )
        let advertisement = MockAdvertisement(localName: "sps", manufacturerData: manufacturerData)
        let thermometer = try XCTUnwrap(InkbirdAdvertisement.Thermometer(advertisement))
        XCTAssertEqual(thermometer.name, .sps)
        XCTAssertEqual(thermometer.manufacturingData, ManufacturingData(bytes: hex("7C 09 FD 17 00 E8 56 64 08")))
        XCTAssertEqual(InkbirdAdvertisement(advertisement), .thermometer(thermometer))
    }

    /// Synthetic payload: -5.25 °C, 45 %. No negative reading has been captured yet.
    func testNegativeTemperature() throws {
        let reading = try XCTUnwrap(ManufacturingData(bytes: hex("F3 FD 94 11 00 5C 05 64 08")))
        XCTAssertEqual(reading.temperature.rawValue, -525)
        XCTAssertEqual(reading.temperature.celcius, -5.25)
        XCTAssertEqual(reading.humidity.percentage, 45)
    }

    func testInvalidPayloads() {
        // CRC byte changed
        XCTAssertNil(ManufacturingData(bytes: hex("7C 09 FD 17 00 E9 56 64 08")))
        // temperature changed, CRC not updated
        XCTAssertNil(ManufacturingData(bytes: hex("7D 09 FD 17 00 E8 56 64 08")))
        // wrong length
        XCTAssertNil(ManufacturingData(bytes: hex("7C 09 FD 17 00 E8 56 64")))
        XCTAssertNil(ManufacturingData(bytes: []))
        // Apple device seen in the same scan, also 9 bytes
        XCTAssertNil(ManufacturingData(bytes: hex("4C 00 10 05 07 14 92 8A 98")))
        // valid payload, but a different name
        let manufacturerData = GATT.ManufacturerSpecificData<Data>(
            companyIdentifier: 0x097C,
            additionalData: Data(hex("FD 17 00 E8 56 64 08"))
        )
        XCTAssertNil(InkbirdAdvertisement.Thermometer(MockAdvertisement(localName: "Bedroom TV", manufacturerData: manufacturerData)))
        XCTAssertNil(InkbirdAdvertisement.Thermometer(MockAdvertisement(localName: nil, manufacturerData: manufacturerData)))
    }

    func testCRC() {
        // CRC-16/MODBUS check value
        XCTAssertEqual(UInt16(crc16Modbus: Array("123456789".utf8)), 0x4B37)
        XCTAssertEqual(UInt16(crc16Modbus: hex("7C 09 FD 17 00")), 0x56E8)
    }
}

// MARK: - Supporting Types

private struct MockAdvertisement: GATT.AdvertisementData {

    typealias Data = Foundation.Data

    var localName: String?

    var manufacturerData: GATT.ManufacturerSpecificData<Data>?

    var txPowerLevel: Double? { nil }

    var serviceData: [BluetoothUUID: Data]? { nil }

    var serviceUUIDs: [BluetoothUUID]? { [.inkbirdThermostat] }

    var solicitedServiceUUIDs: [BluetoothUUID]? { nil }
}

private func hex(_ string: String) -> [UInt8] {
    string.split(separator: " ").compactMap { UInt8($0, radix: 16) }
}
