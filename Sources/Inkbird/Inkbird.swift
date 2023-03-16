import Foundation
import Bluetooth
import GATT

public enum InkbirdAdvertisement: Equatable, Hashable {
    
    case thermometer(Thermometer)
}
