//
//  pokecodec_homeApp.swift
//  pokecodec-home
//
//  Created by chenmengchieh on 2026/1/1.
//

import SwiftUI
import SwiftData

@main
struct pokecodec_homeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }// 指定我們要使用的資料模型
        .modelContainer(for: [Pokemon.self, ConnectedDevice.self, TeamHistory.self, PokeBox.self])
    }
}
