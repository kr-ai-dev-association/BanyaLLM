//
//  ConversationHistory.swift
//  BanyaLLM
//
//  Created by Tony-M4 on 11/13/25.
//

import Foundation

/// 대화 턴 (사용자 질문 + LLM 응답)
struct ConversationTurn: Codable {
    let userQuestion: String
    let aiResponse: String
    let timestamp: Date
}

/// 대화 히스토리 관리
class ConversationHistoryManager {
    private let maxTurns = 3  // 최대 저장할 대화 턴 수
    private let storageKey = "conversationHistory"
    
    /// 대화 턴 저장
    func saveTurn(userQuestion: String, aiResponse: String) {
        var history = loadHistory()
        
        // 새 턴 추가
        let newTurn = ConversationTurn(
            userQuestion: userQuestion,
            aiResponse: aiResponse,
            timestamp: Date()
        )
        history.append(newTurn)
        
        // 최대 턴 수만큼만 유지 (오래된 것 제거)
        if history.count > maxTurns {
            history.removeFirst(history.count - maxTurns)
        }
        
        // UserDefaults에 저장
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
            print("💾 대화 히스토리 저장 완료: \(history.count)턴")
        }
    }
    
    /// 대화 히스토리 불러오기
    func loadHistory() -> [ConversationTurn] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let history = try? JSONDecoder().decode([ConversationTurn].self, from: data) else {
            return []
        }
        return history
    }
    
    /// 대화 히스토리 초기화
    func clearHistory() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        print("🗑️ 대화 히스토리 초기화 완료")
    }
    
    /// 최근 N턴의 사용자 질문만 반환
    func getRecentUserQuestions(count: Int = 2) -> [String] {
        let history = loadHistory()
        return history.suffix(count).map { $0.userQuestion }
    }
}

