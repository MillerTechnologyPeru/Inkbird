//
//  CapturedPacketTests.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import XCTest
@testable import Inkbird

/// Decodes values captured from IBS-TH2 `49:22:08:15:04:CB` on 2026-10-28: a GATT survey, and a PacketLogger
/// capture of the Inkbird app (iOS) syncing history at about 22:27. Expected values were checked against the bytes.
final class CapturedPacketTests: XCTestCase {

    func testLiveReading() throws {
        // survey, 22:25:09
        let reading = try XCTUnwrap(InkbirdReading(bytes: hex("89 0A 16 16 00 15 A3")))
        XCTAssertEqual(reading.temperature, 26.97, accuracy: 0.001)
        XCTAssertEqual(reading.humidity, 56.54, accuracy: 0.001)
        XCTAssertEqual(reading.probe, .builtIn)
        // read by the Inkbird app during the sync, and after it
        XCTAssertEqual(try XCTUnwrap(InkbirdReading(bytes: hex("8B 0A 0B 16 00 FC 65"))).humidity, 56.43, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(InkbirdReading(bytes: hex("8A 0A E6 15 00 51 60"))).temperature, 26.98, accuracy: 0.001)
        // bad CRC, wrong length
        XCTAssertNil(InkbirdReading(bytes: hex("89 0A 16 16 00 15 A4")))
        XCTAssertNil(InkbirdReading(bytes: hex("89 0A 16 16 00 15")))
    }

    func testSettings() throws {
        let settings = try XCTUnwrap(InkbirdSettings(bytes: hex("00 00 00 00 00 00 00 78 00 00 00 32 2D 33 AF 8C 00 00 00 00")))
        XCTAssertEqual(settings.interval, 120)
        XCTAssertNil(InkbirdSettings(bytes: hex("00 00 00 00 00 00 00 79 00 00 00 32 2D 33 AF 8C 00 00 00 00")))
    }

    func testRequests() {
        // order sent by the Inkbird app
        let requests: [InkbirdHistoryRequest] = [
            .temperatureHeader, .temperatureRecords, .temperatureChecksum,
            .humidityHeader, .humidityRecords, .humidityChecksum
        ]
        XCTAssertEqual(requests.map { $0.rawValue }, [0x02, 0x01, 0x07, 0x04, 0x03, 0x08])
        XCTAssertEqual(InkbirdHistoryBuffer.allCases.flatMap { [$0.header, $0.records, $0.checksum] }, requests)
    }

    func testHeaderAndChecksum() throws {
        let header = hex("30 75 00 00 1E FE 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        XCTAssertEqual(InkbirdHistoryReply.header(header), 30000)
        XCTAssertNil(InkbirdHistoryReply.header(hex("31 75 00 00 1E FE 00 00 00 00 00 00 00 00 00 00 00 00 00 00")))
        let temperature = try Self.fixture("history-temperature")
        let humidity = try Self.fixture("history-humidity")
        XCTAssertEqual(InkbirdHistoryReply.checksum(hex("AF 9B 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")), UInt16(crc16Modbus: temperature))
        XCTAssertEqual(InkbirdHistoryReply.checksum(hex("FF 9F 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")), UInt16(crc16Modbus: humidity))
    }

    func testHistory() throws {
        let temperature = try Self.fixture("history-temperature")
        let humidity = try Self.fixture("history-humidity")
        XCTAssertEqual(temperature.count, 12000)
        XCTAssertEqual(Array(temperature.prefix(20)), hex("89 08 56 08 3D 08 6F 08 7C 08 30 08 63 08 35 08 1A 08 4B 08"))
        let end = Date(timeIntervalSince1970: 1_793_240_854) // 2026-10-29 02:27:34 UTC
        let history = InkbirdHistoryReading.decode(temperature: temperature, humidity: humidity, end: end, interval: 120)
        XCTAssertEqual(history.count, 6000)
        // oldest first
        XCTAssertEqual(history[0].temperature, 21.85, accuracy: 0.001)
        XCTAssertEqual(history[0].humidity, 65.28, accuracy: 0.001)
        XCTAssertEqual(history[0].date, end.addingTimeInterval(-5999 * 120))
        // newest last: warmed by hand just before the sync
        XCTAssertEqual(history.suffix(3).map { $0.temperature }, [24.47, 26.54, 26.96])
        XCTAssertEqual(history[5999].humidity, 56.29, accuracy: 0.001)
        XCTAssertEqual(history[5999].date, end)
        XCTAssertEqual(history.map { $0.temperature }.min(), 15.35)
        XCTAssertEqual(history.map { $0.temperature }.max(), 39.02)
    }

    func testHistoryDifferentLengths() {
        // the newest records line up
        let history = InkbirdHistoryReading.decode(
            temperature: hex("10 0A 20 0A 30 0A"),
            humidity: hex("88 13 70 17"),
            end: Date(timeIntervalSince1970: 1000),
            interval: 60
        )
        XCTAssertEqual(history.map { $0.temperature }, [25.92, 26.08])
        XCTAssertEqual(history.map { $0.humidity }, [50, 60])
        XCTAssertEqual(history.map { $0.date.timeIntervalSince1970 }, [940, 1000])
    }

    static func fixture(_ name: String) throws -> [UInt8] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "bin", subdirectory: "Resources"))
        return try Array(Data(contentsOf: url))
    }
}

private func hex(_ string: String) -> [UInt8] {
    string.split(separator: " ").compactMap { UInt8($0, radix: 16) }
}
