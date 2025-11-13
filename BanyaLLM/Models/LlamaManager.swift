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
    
    nonisolated init() {
        // 초기화는 나중에 수동으로 호출
    }
    
    func initialize() {
        Task {
            await loadModel()
        }
    }
    
    func loadModel() async {
        do {
            // 모델 파일 경로 찾기
            let modelPath = try getModelPath()
            
            loadingProgress = "모델 로딩 중..."
            
            // LlamaContext 생성 및 초기화
            llamaContext = LlamaContext(modelPath: modelPath)
            try await llamaContext?.initialize()
            
            isModelLoaded = true
            loadingProgress = "모델 로드 완료"
            print("✅ 모델이 성공적으로 로드되었습니다: \(modelPath)")
            
        } catch {
            isModelLoaded = false
            loadingProgress = "모델 로드 실패: \(error.localizedDescription)"
            print("❌ 모델 로드 실패: \(error)")
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
                guard let llamaContext = self.llamaContext else {
                    continuation.finish()
                    return
                }
                
                // 실제 LLM 추론은 llama.cpp 통합 후 구현
                // 임시 시뮬레이션
                let responses = [
                    "안녕하세요! ",
                    "무엇을 ",
                    "도와드릴까요? ",
                    "궁금한 ",
                    "점이 ",
                    "있으시면 ",
                    "언제든 ",
                    "물어보세요!"
                ]
                
                for response in responses {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1초
                    continuation.yield(response)
                }
                
                continuation.finish()
            }
        }
    }
}

