//
//  ChatViewModel.swift
//  BanyaLLM
//
//  Created by Tony-M4 on 11/13/25.
//

import Foundation
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    
    let llamaManager: LlamaManager  // public으로 변경하여 UI에서 접근 가능
    
    init(llamaManager: LlamaManager = LlamaManager()) {
        self.llamaManager = llamaManager
        // 모델 초기화
        self.llamaManager.initialize()
    }
    
    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let userMessage = ChatMessage(content: inputText, isUser: true)
        messages.append(userMessage)
        
        let userInput = inputText
        inputText = ""
        
        isLoading = true
        
        // LLM으로 응답 생성
        Task {
            var aiResponse = ""
            let aiMessageIndex = messages.count
            
            // 빈 AI 메시지 추가 (스트리밍을 위해)
            let aiMessage = ChatMessage(content: "", isUser: false)
            messages.append(aiMessage)
            
            // 이전 사용자 질문 2개 추출 (현재 질문 제외)
            let previousQuestions = messages
                .filter { $0.isUser }
                .suffix(3)  // 최근 3개 (현재 질문 + 이전 2개)
                .map { $0.content }
                .dropLast()  // 현재 질문 제외
                .reversed()  // 오래된 것부터
                .map { $0 }
            
            // LLM 스트리밍 응답 (이전 질문 포함)
            for await token in await llamaManager.generate(prompt: userInput, previousQuestions: Array(previousQuestions)) {
                aiResponse += token
                // 메시지 업데이트
                if aiMessageIndex < messages.count {
                    messages[aiMessageIndex] = ChatMessage(
                        content: aiResponse,
                        isUser: false,
                        timestamp: messages[aiMessageIndex].timestamp
                    )
                }
            }
            
            isLoading = false
        }
    }
    
    func clearMessages() {
        messages.removeAll()
    }
}

