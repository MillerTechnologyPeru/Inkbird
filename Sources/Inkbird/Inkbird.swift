import Foundation
import Bluetooth
import GATT

public enum InkbirdAdvertisement: Equatable, Hashable {
    
    case thermometer(Thermometer)
}

public extension InkbirdAdvertisement {
    
    init?<T: GATT.AdvertisementData>(_ advertisementData: T) {
        if let thermometer = Thermometer(advertisementData) {
            self = .thermometer(thermometer)
        } else {
            return nil
        }
    }
}
