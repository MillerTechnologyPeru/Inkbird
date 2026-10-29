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

    func testPadding() throws {
        // the last notification of a 6003-record stream: 3 records, then zeros the checksum leaves out
        let records = try Self.fixture("history-temperature") + hex("97 0A A2 0A A4 0A")
        let padded = records + [UInt8](repeating: 0, count: 14)
        let checksum = UInt16(crc16Modbus: records)
        XCTAssertEqual(InkbirdHistoryReply.records(padded, checksum: checksum), records)
        XCTAssertEqual(InkbirdHistoryReply.records(records, checksum: checksum), records)
        XCTAssertNil(InkbirdHistoryReply.records(padded, checksum: checksum &+ 1))
        XCTAssertEqual(InkbirdHistoryReply.records([], checksum: 0xFFFF), [])
    }

    func testHistory() throws {
        let temperature = try Self.fixture("history-temperature")
        let humidity = try Self.fixture("history-humidity")
        XCTAssertEqual(temperature.count, 12000)
        XCTAssertEqual(Array(temperature.prefix(20)), hex("89 08 56 08 3D 08 6F 08 7C 08 30 08 63 08 35 08 1A 08 4B 08"))
        let end = Date(timeIntervalSince1970: 1_793_240_854) // 2026-10-29 02:27:34 UTC
        let history = InkbirdHistoryReading.decode(temperature: temperature, humidity: humidity, end: end, calendar: Self.utc)
        XCTAssertEqual(history.count, 6000)
        // oldest first
        XCTAssertEqual(history[0].temperature, 21.85, accuracy: 0.001)
        XCTAssertEqual(history[0].humidity, 65.28, accuracy: 0.001)
        XCTAssertEqual(history[0].date, Date(timeIntervalSince1970: 1_789_641_600)) // 2026-09-17 10:40 UTC
        // newest last: warmed by hand just before the sync
        XCTAssertEqual(history.suffix(3).map { $0.temperature }, [24.47, 26.54, 26.96])
        XCTAssertEqual(history[5999].humidity, 56.29, accuracy: 0.001)
        // 02:02, 02:20, 02:22
        XCTAssertEqual(history.suffix(3).map { $0.date.timeIntervalSince1970 }, [1_793_239_320, 1_793_240_400, 1_793_240_520])
        XCTAssertEqual(history.map { $0.temperature }.min(), 15.35)
        XCTAssertEqual(history.map { $0.temperature }.max(), 39.02)
    }

    func testHistoryDifferentLengths() {
        // the newest records line up
        let history = InkbirdHistoryReading.decode(
            temperature: hex("10 0A 20 0A 30 0A"),
            humidity: hex("88 13 70 17"),
            end: Date(timeIntervalSince1970: 1000), // 00:16:40 UTC
            calendar: Self.utc
        )
        XCTAssertEqual(history.map { $0.temperature }, [25.92, 26.08])
        XCTAssertEqual(history.map { $0.humidity }, [50, 60])
        XCTAssertEqual(history.map { $0.date.timeIntervalSince1970 }, [0, 120])
    }

    func testDates() {
        func dates(_ count: Int, _ end: TimeInterval) -> [TimeInterval] {
            InkbirdHistoryReading.dates(count: count, end: Date(timeIntervalSince1970: end), calendar: Self.utc)
                .map { $0.timeIntervalSince1970 }
        }
        // before the second slot of a pair, the newest record is the first slot
        XCTAssertEqual(dates(3, 1200 + 119), [0, 120, 1200])
        // on the second slot
        XCTAssertEqual(dates(3, 1200 + 120), [120, 1200, 1320])
        XCTAssertEqual(dates(0, 1000), [])
    }

    /// Inkbird app (iOS) export of the same sensor, after syncing at 2026-10-29 01:23:11 EDT (05:23:11 UTC).
    /// The app writes a row every 2 minutes, interpolating between records; every record must be at a row with its values.
    func testInkbirdAppExport() throws {
        let temperature = try Self.fixture("history-2026-10-29-temperature")
        let humidity = try Self.fixture("history-2026-10-29-humidity")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let history = InkbirdHistoryReading.decode(
            temperature: temperature,
            humidity: humidity,
            end: Date(timeIntervalSince1970: 1_793_251_391),
            calendar: calendar
        )
        XCTAssertEqual(history.count, 6001)
        // the export starts at 2026-10-27 00:00 EDT
        let rows = try Self.inkbirdExport("IBS-THS-2026-10-29", timeZone: calendar.timeZone)
        XCTAssertEqual(rows.count, 1482)
        let start = try XCTUnwrap(rows.keys.min())
        let exported = history.filter { $0.date >= start }
        XCTAssertEqual(exported.count, 298)
        for reading in exported {
            let row = try XCTUnwrap(rows[reading.date], "\(reading.date)")
            XCTAssertEqual(row.temperature, reading.temperature, accuracy: 0.001, "\(reading.date)")
            XCTAssertEqual(row.humidity, reading.humidity, accuracy: 0.001, "\(reading.date)")
        }
        XCTAssertEqual(history.last?.date, rows.keys.max()) // 01:22
    }

    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Reads an Inkbird app CSV export: UTF-16, tab separated, three header lines.
    static func inkbirdExport(_ name: String, timeZone: TimeZone) throws -> [Date: (temperature: Float, humidity: Float)] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "csv", subdirectory: "Resources"))
        let text = try XCTUnwrap(String(data: Data(contentsOf: url), encoding: .utf16))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MM/dd/yyyy HH:mm:ss"
        var rows = [Date: (temperature: Float, humidity: Float)]()
        for line in text.split(whereSeparator: \.isNewline).dropFirst(3) {
            let fields = line.split(separator: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 4,
                  let date = formatter.date(from: fields[0]),
                  let temperature = Float(fields[1]),
                  let humidity = Float(fields[3]) else {
                continue
            }
            rows[date] = (temperature, humidity)
        }
        return rows
    }

    static func fixture(_ name: String) throws -> [UInt8] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "bin", subdirectory: "Resources"))
        return try Array(Data(contentsOf: url))
    }
}

private func hex(_ string: String) -> [UInt8] {
    string.split(separator: " ").compactMap { UInt8($0, radix: 16) }
}
