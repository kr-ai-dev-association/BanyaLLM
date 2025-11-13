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
            
            // LLM 스트리밍 응답 (대화 히스토리는 LlamaManager에서 자동으로 불러옴)
            for await token in await llamaManager.generate(prompt: userInput) {
                // 빈 문자열이 오면 이전 내용을 지움 (애니메이션 깜빡임 효과)
                if token.isEmpty {
                    aiResponse = ""
                } else {
                    aiResponse += token
                }
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

