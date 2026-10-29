//
//  SensorDetailView.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

import Foundation
import SwiftUI
#if canImport(Charts)
import Charts
#endif
import DarwinGATT
import Inkbird

/// Connects to the selected sensor and shows its reading and stored history.
struct SensorDetailView: View {

    @EnvironmentObject
    var store: Store

    let peripheral: NativeCentral.Peripheral

    @State
    private var reading: InkbirdReading?

    @State
    private var range = HistoryRange.day

    @State
    private var history: [InkbirdHistoryReading]?

    @State
    private var isBusy = false

    @State
    private var isDownloading = false

    @State
    private var error: String?

    var body: some View {
        Form {
            connectionSection
            readingSection
            historySection
        }
        .navigationTitle(InkbirdModel.ibsTH2.rawValue)
        .task { refresh() }
        .onDisappear {
            let peripheral = self.peripheral
            Task {
                await store.disconnect(peripheral)
            }
        }
    }
}

private extension SensorDetailView {

    var connectionSection: some View {
        Section {
            HStack {
                Text(verbatim: peripheral.description)
                    .foregroundColor(.gray)
                Spacer()
                if isBusy {
                    ProgressView()
                } else {
                    Text(store.isConnected(peripheral) ? "Connected" : "Not connected")
                        .foregroundColor(store.isConnected(peripheral) ? .green : .gray)
                }
            }
            Button("Refresh", action: refresh)
                .disabled(isBusy)
            if let error {
                Text(verbatim: error)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder
    var readingSection: some View {
        if let reading {
            Section("Reading") {
                Text("Temperature: \(reading.temperature, specifier: "%.2f") °C")
                Text("Humidity: \(reading.humidity, specifier: "%.2f")%")
                if let batteryLevel {
                    Text("Battery: \(batteryLevel)%")
                }
                if reading.probe != .builtIn {
                    Text(verbatim: "Probe: \(reading.probe)")
                }
            }
        }
    }

    var historySection: some View {
        Section("History") {
            Picker("Range", selection: $range) {
                ForEach(HistoryRange.allCases) {
                    Text($0.title).tag($0)
                }
            }
            .pickerStyle(.segmented)
            Button("Load History") { loadHistory() }
                .disabled(isBusy)
            if isDownloading {
                Text("Downloading, this takes about 90 seconds…")
                    .foregroundColor(.gray)
                    .font(.footnote)
            }
            if let history {
                HistoryView(readings: range.filter(history))
            }
        }
    }

    /// Battery from the last advertisement. The live reading does not include it.
    var batteryLevel: UInt8? {
        guard case let .thermometer(thermometer) = store.peripherals[peripheral] else {
            return nil
        }
        return thermometer.manufacturingData.batteryLevel.rawValue
    }

    func refresh() {
        perform {
            reading = try await store.readLive(peripheral)
        }
    }

    func loadHistory() {
        perform {
            isDownloading = true
            defer { isDownloading = false }
            history = try await store.history(peripheral)
        }
    }

    /// Runs a sensor action, tracking progress and errors.
    func perform(_ action: @escaping @MainActor () async throws -> ()) {
        Task { @MainActor in
            isBusy = true
            defer { isBusy = false }
            do {
                try await action()
                error = nil
            }
            catch {
                self.error = String(describing: error)
            }
        }
    }
}

// MARK: - History

private extension SensorDetailView {

    enum HistoryRange: String, CaseIterable, Identifiable {

        case day
        case week
        case all

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .day: return "1 Day"
            case .week: return "1 Week"
            case .all: return "All"
            }
        }

        /// The sensor always sends its whole history, so the range only filters what is shown.
        func filter(_ readings: [InkbirdHistoryReading]) -> [InkbirdHistoryReading] {
            let interval: TimeInterval
            switch self {
            case .day: interval = 24 * 60 * 60
            case .week: interval = 7 * 24 * 60 * 60
            case .all: return readings
            }
            let start = Date().addingTimeInterval(-interval)
            return readings.filter { $0.date >= start }
        }
    }

    struct HistoryView: View {

        let readings: [InkbirdHistoryReading]

        var body: some View {
            if let first = readings.first {
                let temperatures = readings.map { $0.temperature }
                let humidity = readings.map { $0.humidity }
                Text("\(readings.count) readings since \(first.date.formatted(date: .abbreviated, time: .shortened))")
                Text("Temperature: \(temperatures.min()!, specifier: "%.1f") – \(temperatures.max()!, specifier: "%.1f") °C")
                Text("Humidity: \(humidity.min()!, specifier: "%.1f") – \(humidity.max()!, specifier: "%.1f")%")
                #if canImport(Charts)
                if #available(iOS 16, *) {
                    HistoryChart(readings: readings)
                        .frame(height: 200)
                }
                #endif
            } else {
                Text("No readings stored")
                    .foregroundColor(.gray)
            }
        }
    }
}

#if canImport(Charts)
@available(iOS 16, *)
private struct HistoryChart: View {

    let readings: [InkbirdHistoryReading]

    var body: some View {
        Chart(readings, id: \.date) { reading in
            LineMark(
                x: .value("Time", reading.date),
                y: .value("Temperature", reading.temperature)
            )
            .foregroundStyle(.orange)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel("°C")
    }
}
#endif
