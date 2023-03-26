import Foundation
import SwiftUI
import CoreBluetooth
import Bluetooth
import GATT
import Inkbird

@main
struct InkbirdApp: App {
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(Store.shared)
        }
    }
}
