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
}
