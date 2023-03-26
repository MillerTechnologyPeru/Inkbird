//
//  InkbirdAdvertisementRow.swift
//  
//
//  Created by Alsey Coleman Miller on 3/25/23.
//

import Foundation
import SwiftUI
import Inkbird

struct InkbirdAdvertisementRow: View {
    
    let advertisement: InkbirdAdvertisement
    
    var body: some View {
        switch advertisement {
        case .thermometer(let thermometer):
            return AnyView(Thermometer(advertisement: thermometer))
        }
    }
}

extension InkbirdAdvertisementRow {
    
    struct Thermometer: View {
        
        let advertisement: InkbirdAdvertisement.Thermometer
        
        var body: some View {
            VStack(alignment: .leading) {
                Text("Thermometer")
                    .font(.title3)
                Text(verbatim: model)
                    .foregroundColor(.gray)
                    .font(.subheadline)
                Text("Battery: \(batteryLevel) %")
                    .font(.subheadline)
                Text("Temperature: \(temperature) C°")
                    .font(.subheadline)
                Text("Humidity: \(humidity) %")
                    .font(.subheadline)
            }
        }
    }
}

private extension InkbirdAdvertisementRow.Thermometer {
    
    var model: String {
        advertisement.name.rawValue
    }
    
    var batteryLevel: String {
        advertisement.manufacturingData.batteryLevel.rawValue.description
    }
    
    var temperature: String {
        format(advertisement.manufacturingData.temperature.celcius)
    }
    
    var humidity: String {
        format(advertisement.manufacturingData.humidity.percentage)
    }
    
    func format(_ float: Float) -> String {
        String(format: "%.2f", float)
    }
}

#if DEBUG
struct InkbirdAdvertisementRow_Previews: PreviewProvider {
    static var previews: some View {
        InkbirdAdvertisementRow(advertisement: .thermometer(.mock))
    }
}
#endif
