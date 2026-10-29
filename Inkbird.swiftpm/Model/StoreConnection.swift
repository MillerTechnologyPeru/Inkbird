//
//  StoreConnection.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import Bluetooth
import GATT
import DarwinGATT
import Inkbird

// MARK: - Connection

public extension Store {

    /// Whether there is an open connection to the sensor.
    func isConnected(_ peripheral: NativeCentral.Peripheral) -> Bool {
        connections[peripheral] != nil
    }

    /// Returns the open connection to the sensor, connecting first if needed.
    @discardableResult
    func connect(to peripheral: NativeCentral.Peripheral) async throws -> InkbirdConnection<NativeCentral> {
        if let connection = connections[peripheral], await connection.isConnected {
            return connection
        }
        // scanning slows down connecting
        if isScanning {
            stopScanning()
            log("Stopped scanning to connect")
        }
        log("Connecting to \(peripheral)")
        let connection = try await central.connect(to: peripheral, model: .ibsTH2)
        connections[peripheral] = connection
        log("Connected to \(peripheral)")
        // events end when the sensor closes the connection
        Task { [weak self] in
            for await event in connection.events {
                self?.log("\(peripheral) unexpected notification \(event)")
            }
            self?.connectionClosed(peripheral, connection)
        }
        return connection
    }

    /// Closes the connection to the sensor.
    func disconnect(_ peripheral: NativeCentral.Peripheral) async {
        guard let connection = connections[peripheral] else {
            return
        }
        connections[peripheral] = nil
        await connection.disconnect()
        log("Disconnected from \(peripheral)")
    }

    /// Runs an operation on the connection to the sensor, connecting first if needed.
    func perform<T: Sendable>(
        on peripheral: NativeCentral.Peripheral,
        _ operation: (InkbirdConnection<NativeCentral>) async throws -> T
    ) async throws -> T {
        let connection = try await connect(to: peripheral)
        do {
            return try await operation(connection)
        }
        catch InkbirdConnectionError.disconnected {
            connectionClosed(peripheral, connection)
            throw InkbirdConnectionError.disconnected
        }
        catch InkbirdConnectionError.timeout {
            // the sensor may have gone away without disconnecting; reconnect next time
            await disconnect(peripheral)
            throw InkbirdConnectionError.timeout
        }
    }

    /// Reads the current temperature and humidity.
    func readLive(_ peripheral: NativeCentral.Peripheral) async throws -> InkbirdReading {
        let reading = try await perform(on: peripheral) {
            try await $0.readLive()
        }
        log("\(peripheral) reading \(reading.temperature) °C \(reading.humidity) %")
        return reading
    }

    /// Downloads the readings stored on the sensor, oldest first.
    ///
    /// Takes about 90 seconds for a full sensor.
    func history(_ peripheral: NativeCentral.Peripheral) async throws -> [InkbirdHistoryReading] {
        log("\(peripheral) downloading history")
        let start = Date()
        let history = try await perform(on: peripheral) {
            try await $0.history()
        }
        log("\(peripheral) downloaded \(history.count) readings in \(Int(Date().timeIntervalSince(start))) s")
        return history
    }
}

private extension Store {

    /// Forgets a connection the sensor closed.
    func connectionClosed(_ peripheral: NativeCentral.Peripheral, _ connection: InkbirdConnection<NativeCentral>) {
        guard connections[peripheral] === connection else {
            return
        }
        connections[peripheral] = nil
        log("\(peripheral) closed the connection")
    }
}
