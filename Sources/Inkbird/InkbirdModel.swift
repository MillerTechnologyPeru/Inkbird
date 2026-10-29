//
//  InkbirdModel.swift
//
//
//  Created by Alsey Coleman Miller on 10/29/26.
//

/// Inkbird device model.
public enum InkbirdModel: String, Codable, CaseIterable, Sendable {

    /// IBS-TH2 temperature and humidity sensor.
    case ibsTH2 = "IBS-TH2"
}
