//
//  BanyaLLMApp.swift
//  BanyaLLM
//
//  Created by Tony-M4 on 11/13/25.
//

import SwiftUI

@main
struct BanyaLLMApp: App {
    init() {
        // 앱 시작 시 대화 히스토리 초기화
        let historyManager = ConversationHistoryManager()
        historyManager.clearHistory()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
