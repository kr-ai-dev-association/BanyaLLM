//
//  LlamaManager.swift
//  BanyaLLM
//
//  Created by Tony-M4 on 11/13/25.
//

import Foundation

@MainActor
class LlamaManager: ObservableObject {
    @Published var isModelLoaded: Bool = false
    @Published var loadingProgress: String = ""
    
    private var llamaContext: LlamaContext?
    private let modelFilename = "llama31-banyaa-q4_k_m.gguf"
    
    // Llama 3.1 System Prompt (대화 품질 향상)
    private let systemPrompt = """
당신은 매우 간결하고 명확한 한국어 대화 전문가입니다.
항상 한국어로만 대답하며, 질문에 핵심만 1-2문장으로 답변합니다.
절대 반복하지 않고, 같은 내용을 두 번 말하지 않습니다.
장황한 설명이나 불필요한 예시를 피하고, 핵심만 간단히 말합니다.
모르는 정보는 "죄송하지만 그 정보는 알 수 없습니다"라고만 답변합니다.
"""
    
    nonisolated init() {
        // 초기화는 나중에 수동으로 호출
    }
    
    func initialize() {
        Task {
            await loadModel()
        }
    }
    
    // MARK: - Llama 3.1 Chat Template
    
    /// Llama 3.1 공식 Chat Template 적용
    /// - Parameter userMessage: 사용자 메시지
    /// - Returns: 포맷된 전체 프롬프트
    private func formatChatPrompt(userMessage: String) -> String {
        let bos = "<|begin_of_text|>"
        let startHeader = "<|start_header_id|>"
        let endHeader = "<|end_header_id|>"
        let eot = "<|eot_id|>"
        
        let formattedPrompt = """
\(bos)\(startHeader)system\(endHeader)

\(systemPrompt)\(eot)\(startHeader)user\(endHeader)

\(userMessage)\(eot)\(startHeader)assistant\(endHeader)

"""
        
        return formattedPrompt
    }
    
    func loadModel() async {
        do {
            // 1. 저장된 모델 경로 확인
            if let savedPath = UserDefaults.standard.string(forKey: "selectedModelPath") {
                print("💾 저장된 모델 경로 발견: \(savedPath)")
                
                if FileManager.default.fileExists(atPath: savedPath) {
                    print("✅ 저장된 경로에 파일 존재 - 자동 로드 시도")
                    let success = await loadModelFromPath(savedPath)
                    
                    if success {
                        print("✅ 저장된 모델 자동 로드 성공")
                        return
                    } else {
                        print("⚠️ 저장된 모델 로드 실패 - 경로 제거")
                        UserDefaults.standard.removeObject(forKey: "selectedModelPath")
                    }
                } else {
                    print("⚠️ 저장된 경로에 파일 없음 - 경로 제거")
                    UserDefaults.standard.removeObject(forKey: "selectedModelPath")
                }
            }
            
            // 2. 기본 경로에서 모델 찾기
            print("🔍 기본 경로에서 모델 검색")
            let modelPath = try getModelPath()
            await loadModelFromPath(modelPath)
            
        } catch {
            isModelLoaded = false
            loadingProgress = "모델 파일을 선택해주세요"
            print("ℹ️ 모델 파일 선택 필요")
        }
    }
    
    @discardableResult
    func loadModelFromPath(_ path: String) async -> Bool {
        do {
            loadingProgress = "모델 로딩 중..."
            print("📂 모델 로드 시작: \(path)")
            
            // LlamaContext 생성 및 초기화
            llamaContext = LlamaContext(modelPath: path)
            try await llamaContext?.initialize()
            
            isModelLoaded = true
            loadingProgress = "모델 로드 완료"
            print("✅ 모델이 성공적으로 로드되었습니다")
            
            // 성공 시 경로 저장
            UserDefaults.standard.set(path, forKey: "selectedModelPath")
            print("💾 모델 경로 저장: \(path)")
            
            return true
            
        } catch {
            isModelLoaded = false
            loadingProgress = "모델 로드 실패: \(error.localizedDescription)"
            print("❌ 모델 로드 실패: \(error)")
            
            return false
        }
    }
    
    private func getModelPath() throws -> String {
        // 프로젝트 루트에서 모델 파일 찾기 (개발 중)
        let projectPath = "/Volumes/Transcend/Projects/BanyaLLM/BanyaLLM/\(modelFilename)"
        if FileManager.default.fileExists(atPath: projectPath) {
            print("📁 모델 경로: \(projectPath)")
            return projectPath
        }
        
        // Documents 디렉토리에서 찾기
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelPath = documentsPath.appendingPathComponent(modelFilename).path
        
        if FileManager.default.fileExists(atPath: modelPath) {
            print("📁 모델 경로: \(modelPath)")
            return modelPath
        }
        
        // Bundle에서 모델 파일 찾기 (배포 시)
        if let path = Bundle.main.path(forResource: "llama31-banyaa-q4_k_m", ofType: "gguf") {
            print("📁 모델 경로: \(path)")
            return path
        }
        
        print("❌ 모델 파일을 찾을 수 없습니다")
        print("다음 경로를 확인해주세요:")
        print("1. \(projectPath)")
        print("2. \(modelPath)")
        
        throw LlamaError.modelNotFound
    }
    
    func generate(prompt: String) async -> AsyncStream<String> {
        return AsyncStream { continuation in
            Task {
                #if targetEnvironment(simulator)
                // 시뮬레이터: 간단한 응답 생성
                let responses = [
                    "안녕하세요! 저는 BanyaLLM입니다.",
                    "\n\n",
                    "현재 시뮬레이터에서 실행 중이라 시뮬레이션 모드로 동작합니다.",
                    "\n\n",
                    "실제 LLM을 사용하려면 iPhone이나 iPad 실제 기기에서 실행해주세요!",
                    "\n\n",
                    "질문: \"\(prompt)\""
                ]
                
                for token in responses {
                    continuation.yield(token)
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                continuation.finish()
                #else
                
                    guard let llamaContext = self.llamaContext else {
                        print("❌ LlamaContext가 초기화되지 않았습니다")
                        continuation.yield("모델이 로드되지 않았습니다. 앱을 재시작해주세요.")
                        continuation.finish()
                        return
                    }
                    
                    // Llama 3.1 Chat Template 적용
                    let formattedPrompt = self.formatChatPrompt(userMessage: prompt)
                    
                    // LLM 추론 초기화
                    await llamaContext.completionInit(text: formattedPrompt)
                    
                    // 스트리밍 응답 생성 (강화된 특수 토큰 필터링)
                    var accumulatedRaw = ""
                    var previousCleanedLength = 0
                    let specialTokenPatterns = [
                        "<|begin_of_text|>",
                        "<|end_of_text|>",
                        "<|start_header_id|>",
                        "<|end_header_id|>",
                        "<|eot_id|>",
                        "<|eom_id|>",
                        "<|python_tag|>",
                        "<|finetune_right_pad_id|>"
                    ]
                    
                    func filterSpecialTokens(_ text: String) -> String {
                        var cleaned = text
                        
                        // 1. 완전한 특수 토큰 패턴 제거 (반복적으로 제거하여 중첩 패턴도 처리)
                        var previousLength = 0
                        while cleaned.count != previousLength {
                            previousLength = cleaned.count
                            for pattern in specialTokenPatterns {
                                cleaned = cleaned.replacingOccurrences(of: pattern, with: "")
                            }
                        }
                        
                        // 2. reserved_special_token 패턴 제거
                        if let regex = try? NSRegularExpression(pattern: "<\\|reserved_special_token_\\d+\\|>", options: []) {
                            let range = NSRange(cleaned.startIndex..., in: cleaned)
                            cleaned = regex.stringByReplacingMatches(
                                in: cleaned,
                                options: [],
                                range: range,
                                withTemplate: ""
                            )
                        }
                        
                        // 3. 부분 특수 토큰 패턴 제거 (슬라이딩 윈도우)
                        // 최근 30자 내에서 "<|" + "|>" 조합 찾기
                        let windowSize = 30
                        if cleaned.count >= windowSize {
                            let recentText = String(cleaned.suffix(windowSize))
                            // "<|"로 시작하고 "|>"로 끝나는 패턴 찾기
                            if let startIndex = recentText.lastIndex(of: "<"),
                               let pipeAfter = recentText.index(startIndex, offsetBy: 1, limitedBy: recentText.endIndex),
                               pipeAfter < recentText.endIndex && recentText[pipeAfter] == "|",
                               let endIndex = recentText.range(of: "|>", range: pipeAfter..<recentText.endIndex)?.upperBound {
                                // 특수 토큰 패턴 발견: 전체 텍스트에서 해당 부분 제거
                                let globalStartOffset = cleaned.count - windowSize + recentText.distance(from: recentText.startIndex, to: startIndex)
                                let globalEndOffset = cleaned.count - windowSize + recentText.distance(from: recentText.startIndex, to: endIndex)
                                
                                let globalStart = cleaned.index(cleaned.startIndex, offsetBy: globalStartOffset)
                                let globalEnd = cleaned.index(cleaned.startIndex, offsetBy: globalEndOffset)
                                cleaned = String(cleaned[..<globalStart]) + String(cleaned[globalEnd...])
                            }
                        }
                        
                        return cleaned
                    }
                    
                    while await !llamaContext.isDone {
                        let token = await llamaContext.completionLoop()
                        
                        if !token.isEmpty {
                            accumulatedRaw += token
                            
                            // 강화된 특수 토큰 필터링
                            var cleanedText = filterSpecialTokens(accumulatedRaw)
                            
                            // 이전에 출력한 부분을 제외하고 새로운 부분만 출력
                            if cleanedText.count > previousCleanedLength {
                                let newContent = String(cleanedText.dropFirst(previousCleanedLength))
                                if !newContent.isEmpty {
                                    continuation.yield(newContent)
                                    previousCleanedLength = cleanedText.count
                                }
                            } else if cleanedText.count < previousCleanedLength {
                                // 필터링으로 인해 텍스트가 줄어든 경우 (특수 토큰 제거됨)
                                previousCleanedLength = cleanedText.count
                            }
                            
                            // 자연스러운 타이핑 효과
                            try? await Task.sleep(nanoseconds: 50_000_000)
                        }
                    }
                    
                    // 추론 완료 후 정리
                    await llamaContext.clear()
                    continuation.finish()
                #endif
            }
        }
    }
}

