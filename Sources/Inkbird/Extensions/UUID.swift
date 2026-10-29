//
//  UUID.swift
//
//
//  Created by Alsey Coleman Miller on 3/15/23.
//

import Foundation
import Bluetooth

public extension BluetoothUUID {

    /// Inkbird Thermostat
    static var inkbirdThermostat: BluetoothUUID {
        .bit16(0xFFF0)
    }

    /// Inkbird settings (`cfg data`), including the logging interval.
    static var inkbirdSettings: BluetoothUUID {
        .bit16(0xFFF1)
    }

    /// Inkbird live reading (`Real time data`).
    static var inkbirdRealTimeData: BluetoothUUID {
        .bit16(0xFFF2)
    }

    /// Inkbird record counter (`recoder frame`).
    static var inkbirdRecordCount: BluetoothUUID {
        .bit16(0xFFF5)
    }

    /// Inkbird history replies (`history data`).
    static var inkbirdHistoryData: BluetoothUUID {
        .bit16(0xFFF6)
    }

    /// Inkbird history requests (`his data type`).
    static var inkbirdHistoryRequest: BluetoothUUID {
        .bit16(0xFFF8)
    }
}
