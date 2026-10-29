//
//  CRC16.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

internal extension UInt16 {

    /// CRC-16/MODBUS (polynomial `0xA001` reflected, initial value `0xFFFF`, no final XOR).
    ///
    /// Inkbird sensors use it for advertisements, characteristic values and history transfers.
    init<C: Collection>(crc16Modbus bytes: C) where C.Element == UInt8 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0 ..< 8 {
                crc = crc & 1 != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        self = crc
    }
}
