import Foundation
import XCTest
@testable import Inkbird
import Bluetooth
import GATT
import BluetoothGAP
import BluetoothHCI
import BluetoothGATT

final class InkbirdTests: XCTestCase {
    
    func testThermostatAdvertisement() {
        
        do {
            /*
             Parameter Length: 42 (0x2A)
             Num Reports: 0X01
             Report 0
                 Event Type: Connectable Advertising - Scannable Advertising - Scan Response - Legacy Advertising PDUs Used - Complete -
                 Address Type: Public
                 Peer Address: 49:22:08:15:04:CB
                 Primary PHY: 1M
                 Secondary PHY: No Packets
                 Advertising SID: Unavailable
                 Tx Power: Unavailable
                 RSSI: -55 dBm
                 Periodic Advertising Interval: 0.000000ms (0x0)
                 Direct Address Type: Public
                 Direct Address: 00:00:00:00:00:00
                 Data Length: 16
                 Local Name: sps
                 Data: 04 09 73 70 73 0A FF E5 07 75 1D 00 70 28 64 08
             */
            
            let advertisementData: LowEnergyAdvertisingData = [0x04, 0x09, 0x73, 0x70, 0x73, 0x0A, 0xFF, 0xE5, 0x07, 0x75, 0x1D, 0x00, 0x70, 0x28, 0x64, 0x08]
            
            XCTAssertEqual(advertisementData.localName, "sps")
            guard let thermometer = InkbirdAdvertisement.Thermometer(advertisementData) else {
                XCTFail("Unable to parse.")
                return
            }
            
            XCTAssertEqual(thermometer.name, .sps)
            XCTAssertEqual(thermometer.manufacturingData.batteryLevel, 100)
            XCTAssertEqual(thermometer.manufacturingData.temperature.rawValue, 2021)
            XCTAssertEqual(thermometer.manufacturingData.temperature.celcius, 20.21)
            XCTAssertEqual(thermometer.manufacturingData.humidity.rawValue, 7541)
            XCTAssertEqual(thermometer.manufacturingData.humidity.percentage, 75.41)
        }
        
        do {
            /*
             Parameter Length: 42 (0x2A)
             Num Reports: 0X01
             Report 0
                 Event Type: Connectable Advertising - Scannable Advertising - Scan Response - Legacy Advertising PDUs Used - Complete -
                 Address Type: Public
                 Peer Address: 49:22:08:15:04:CB
                 Primary PHY: 1M
                 Secondary PHY: No Packets
                 Advertising SID: Unavailable
                 Tx Power: Unavailable
                 RSSI: -50 dBm
                 Periodic Advertising Interval: 0.000000ms (0x0)
                 Direct Address Type: Public
                 Direct Address: 00:00:00:00:00:00
                 Data Length: 16
                 Local Name: sps
                 Data: 04 09 73 70 73 0A FF 49 08 39 1C 00 23 63 64 08
             */
            
            let advertisementData: LowEnergyAdvertisingData = [0x04, 0x09, 0x73, 0x70, 0x73, 0x0A, 0xFF, 0x49, 0x08, 0x39, 0x1C, 0x00, 0x23, 0x63, 0x64, 0x08]
            
            XCTAssertEqual(advertisementData.localName, "sps")
            
            guard let thermometer = InkbirdAdvertisement.Thermometer(advertisementData) else {
                XCTFail("Unable to parse.")
                return
            }
            
            XCTAssertEqual(thermometer.name, .sps)
            XCTAssertEqual(thermometer.manufacturingData.batteryLevel, 100)
            XCTAssertEqual(thermometer.manufacturingData.temperature.rawValue, 2121)
            XCTAssertEqual(thermometer.manufacturingData.temperature.celcius, 21.21)
            XCTAssertEqual(thermometer.manufacturingData.humidity.rawValue, 7225)
            XCTAssertEqual(thermometer.manufacturingData.humidity.percentage, 72.25)
        }
        
        do {
            
            /*
             Parameter Length: 42 (0x2A)
             Num Reports: 0X01
             Report 0
                 Event Type: Connectable Advertising - Scannable Advertising - Scan Response - Legacy Advertising PDUs Used - Complete -
                 Address Type: Public
                 Peer Address: 49:22:08:15:04:CB
                 Primary PHY: 1M
                 Secondary PHY: No Packets
                 Advertising SID: Unavailable
                 Tx Power: Unavailable
                 RSSI: -53 dBm
                 Periodic Advertising Interval: 0.000000ms (0x0)
                 Direct Address Type: Public
                 Direct Address: 00:00:00:00:00:00
                 Data Length: 16
                 Local Name: sps
                 Data: 04 09 73 70 73 0A FF 64 08 D2 1C 00 FF 51 64 08
             */
            
            let advertisementData: LowEnergyAdvertisingData = [0x04, 0x09, 0x73, 0x70, 0x73, 0x0A, 0xFF, 0x64, 0x08, 0xD2, 0x1C, 0x00, 0xFF, 0x51, 0x64, 0x08]
            
            XCTAssertEqual(advertisementData.localName, "sps")
            
            guard let thermometer = InkbirdAdvertisement.Thermometer(advertisementData) else {
                XCTFail("Unable to parse.")
                return
            }
            
            XCTAssertEqual(thermometer.name, .sps)
            XCTAssertEqual(thermometer.manufacturingData.batteryLevel, 100)
            XCTAssertEqual(thermometer.manufacturingData.temperature.rawValue, 2148)
            XCTAssertEqual(thermometer.manufacturingData.temperature.celcius, 21.48)
            XCTAssertEqual(thermometer.manufacturingData.humidity.rawValue, 7378)
            XCTAssertEqual(thermometer.manufacturingData.humidity.percentage, 73.78)
        }
    }
}
