//
//  Item.swift
//  BYEREDX
//
//  Created by Trontap Tangsakol on 12/1/2569 BE.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
