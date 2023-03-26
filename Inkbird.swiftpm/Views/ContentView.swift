import SwiftUI
import Inkbird

struct ContentView: View {
    
    @EnvironmentObject
    var store: Store
    
    var body: some View {
        NavigationView {
            NearbyDevicesView()
        }
    }
}
