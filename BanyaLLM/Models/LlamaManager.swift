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
당신은 친절하고 능숙한 한국어 대화 전문가입니다.
항상 한국어로만 대답하며, 질문에 명확하고 상세하게 답변합니다.
답변은 간결하고 이해하기 쉽게 작성하며, 불필요한 서론은 피합니다.
모르는 정보에 대해서는 솔직하게 "죄송하지만 그 정보는 알 수 없습니다"라고 답변합니다.
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
                    
                    print("🎯 LLM 생성 시작")
                    
                    // Llama 3.1 Chat Template 적용
                    let formattedPrompt = self.formatChatPrompt(userMessage: prompt)
                    
                    // LLM 추론 초기화
                    await llamaContext.completionInit(text: formattedPrompt)
                    
                    // 스트리밍 응답 생성
                    while await !llamaContext.isDone {
                        let token = await llamaContext.completionLoop()
                        
                        if !token.isEmpty {
                            continuation.yield(token)
                            // 자연스러운 타이핑 효과
                            try? await Task.sleep(nanoseconds: 50_000_000)
                        }
                    }
                    
                    print("✅ 생성 완료")
                    
                    // 추론 완료 후 정리
                    await llamaContext.clear()
                    continuation.finish()
                #endif
            }
        }
    }
}

