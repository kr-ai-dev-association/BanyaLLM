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
    
    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let userMessage = ChatMessage(content: inputText, isUser: true)
        messages.append(userMessage)
        
        let userInput = inputText
        inputText = ""
        
        isLoading = true
        
        // LLM 응답 시뮬레이션 (실제 LLM API 연동 시 여기를 수정하세요)
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1초 대기
            
            let response = generateResponse(for: userInput)
            let aiMessage = ChatMessage(content: response, isUser: false)
            messages.append(aiMessage)
            
            isLoading = false
        }
    }
    
    private func generateResponse(for input: String) -> String {
        // TODO: 실제 LLM API 호출로 대체
        let responses = [
            "안녕하세요! 무엇을 도와드릴까요?",
            "좋은 질문이네요. 더 자세히 설명해주시겠어요?",
            "알겠습니다. 제가 도움을 드릴 수 있습니다.",
            "흥미로운 주제네요! 더 많이 알려주세요.",
            "네, 이해했습니다. 다른 궁금한 점이 있으신가요?"
        ]
        return responses.randomElement() ?? "답변을 생성하는 중입니다."
    }
    
    func clearMessages() {
        messages.removeAll()
    }
}

