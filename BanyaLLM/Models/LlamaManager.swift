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
            // 저장된 모델 경로 확인
            if let savedPath = UserDefaults.standard.string(forKey: "selectedModelPath"),
               FileManager.default.fileExists(atPath: savedPath) {
                print("💾 저장된 모델 경로 사용: \(savedPath)")
                await loadModelFromPath(savedPath)
                return
            }
            
            // 기본 경로에서 모델 찾기
            let modelPath = try getModelPath()
            await loadModelFromPath(modelPath)
            
        } catch {
            isModelLoaded = false
            loadingProgress = "모델 파일을 선택해주세요"
            print("ℹ️ 모델 파일 선택 필요")
        }
    }
    
    func loadModelFromPath(_ path: String) async {
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
                
                // LLM 추론 초기화
                await llamaContext.completionInit(text: prompt)
                
                // 스트리밍 응답 생성
                while await !llamaContext.isDone {
                    let token = await llamaContext.completionLoop()
                    
                    if !token.isEmpty {
                        continuation.yield(token)
                        // 자연스러운 타이핑 효과
                        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05초
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

