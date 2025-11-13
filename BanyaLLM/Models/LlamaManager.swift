//
//  LlamaManager.swift
//  BanyaLLM
//
//  Created by Tony-M4 on 11/13/25.
//

import Foundation
import CoreLocation
import Network

@MainActor
class LlamaManager: NSObject, ObservableObject {
    @Published var isModelLoaded: Bool = false
    @Published var loadingProgress: String = ""
    
    private var llamaContext: LlamaContext?
    private let modelFilename = "llama31-banyaa-q4_k_m.gguf"
    private var tavilyService: TavilyService?
    private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        return manager
    }()
    private var currentLocation: CLLocation?
    // IP 위치는 항상 기본값(서울 강남구)을 가지므로 옵셔널이 아님
    private var ipLocation: IPLocation = IPLocation(
        city: "강남구",
        country: "대한민국",
        countryCode: "KR",
        latitude: 37.5172,
        longitude: 127.0473,
        region: "서울특별시",
        timezone: "Asia/Seoul"
    )
    private let ipLocationService = IPLocationService()
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = false
    private let conversationHistory = ConversationHistoryManager()
    
    // Llama 3.1 System Prompt (청소년 일상 지원 에이전트)
    private let systemPrompt = """
사용자의 질문에 직접적으로 답변하세요. 자신의 역할이나 능력을 설명하지 말고, 바로 도움을 제공하세요.

중요: 현재 질문에만 답변하세요
- 항상 [사용자 질문] 섹션의 현재 질문에만 답변하세요
- 이전 대화 맥락은 참고용이며, 이전 질문에 답변하지 마세요
- 이전 대화는 맥락 이해를 위한 참고 자료일 뿐입니다
- 현재 질문과 관련 없는 이전 대화 내용은 무시하세요

답변 규칙:
- 명확하고 상세하게 답변 (5-8문장 정도의 적절한 길이)
- 질문에 필요한 정보를 충분히 제공
- 한 번에 한 가지씩 안내
- 위급한 상황이면 보호자나 119 연락 안내
- 복잡한 요청은 필요한 정보를 먼저 확인
- 물결표, 이모티콘, 과도한 문장부호 사용 금지
- 문장부호는 최대 1개만 사용

인사 응답 규칙:
- 사용자가 인사(안녕, 안녕하세요, 하이, 헬로 등)를 하면 인사에 대해 설명하지 말고 간단히 인사로 응답하세요
- 인사는 1-2문장으로 간단히 답변하세요 (예: "안녕하세요", "안녕하세요! 무엇을 도와드릴까요?")
- 인사의 의미나 정의를 설명하지 마세요

절대 금지:
- "장애인" 관련 표현 사용 금지
- 사용자의 특정 상황이나 조건 명시적 언급 금지
- 현재 날짜, 시간, 위치 정보를 명시적으로 언급하지 않음 (내부적으로만 활용)
- 이전 질문에 대한 답변 금지 (오직 현재 질문에만 답변)

웹 검색 결과 활용:
- 검색 결과가 있으면 그 내용을 자연스럽게 재구성하여 답변
- 검색 결과가 없거나 부적절하면 자신의 지식으로 답변
- 검색 결과를 그대로 나열하지 말고 질문에 맞게 정리
"""
    
    // Tavily API 키 설정 (환경 변수나 설정에서 가져올 수 있음)
    func setTavilyAPIKey(_ apiKey: String) {
        self.tavilyService = TavilyService(apiKey: apiKey)
        // print("✅ Tavily API 키 설정 완료")
    }
    
    nonisolated override init() {
        super.init()
        // 초기화는 나중에 수동으로 호출
    }
    
    func initialize() {
        // 네트워크 연결 상태 모니터링 시작
        startNetworkMonitoring()
        
        // Tavily API 키 자동 설정 (기본값)
        if tavilyService == nil {
            setTavilyAPIKey("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")
        }
        
        Task {
            await loadModel()
            await requestLocationPermission()
            // 위치 권한이 없으면 IP 기반 위치 시도
            if currentLocation == nil {
                await fetchIPLocation()
            }
        }
    }
    
    /// 네트워크 연결 상태 모니터링 시작
    private func startNetworkMonitoring() {
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isNetworkAvailable = path.status == .satisfied
                // print("🌐 네트워크 상태: \(path.status == .satisfied ? "연결됨" : "연결 안 됨")")
            }
        }
        networkMonitor.start(queue: queue)
        
        // 초기 상태 확인
        isNetworkAvailable = networkMonitor.currentPath.status == .satisfied
    }
    
    /// 네트워크 연결 상태 확인
    private func checkNetworkConnection() -> Bool {
        return networkMonitor.currentPath.status == .satisfied
    }
    
    /// IP 기반 위치 정보 가져오기 (위치 권한이 없을 때 사용)
    private func fetchIPLocation() async {
        // print("🌐 IP 기반 위치 정보 가져오기 시도...")
        ipLocation = await ipLocationService.getLocationFromIP()
        // print("✅ IP 기반 위치 정보 획득: \(ipLocation.displayName)")
    }
    
    /// 위치 권한 요청 및 현재 위치 가져오기
    private func requestLocationPermission() async {
        let status = locationManager.authorizationStatus
        
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            // 권한 응답 대기
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        
        let newStatus = locationManager.authorizationStatus
        if newStatus == .authorizedWhenInUse || newStatus == .authorizedAlways {
            locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
            locationManager.startUpdatingLocation()
            
            // 위치 업데이트 대기 (최대 3초)
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            currentLocation = locationManager.location
            locationManager.stopUpdatingLocation()
            
            if currentLocation != nil {
                // print("✅ 현재 위치 정보 획득 완료")
            } else {
                // print("⚠️ 위치 정보를 가져올 수 없습니다")
            }
        } else {
            // print("⚠️ 위치 권한이 없습니다. 날짜/시간 정보만 제공됩니다.")
        }
    }
    
    /// 현재 컨텍스트 정보 가져오기 (날짜, 시간, 위치)
    private func getCurrentContext() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 MM월 dd일 EEEE"
        let dateString = formatter.string(from: Date())
        
        formatter.dateFormat = "HH시 mm분"
        let timeString = formatter.string(from: Date())
        
        var context = "현재 날짜: \(dateString)\n현재 시간: \(timeString)"
        
        // 1순위: GPS 위치 (정확도 높음)
        if let location = currentLocation {
            context += "\n현재 위치: 위도 \(String(format: "%.4f", location.coordinate.latitude)), 경도 \(String(format: "%.4f", location.coordinate.longitude))"
        }
        // 2순위: IP 기반 위치 (대략적 위치)
        else {
            context += "\n현재 위치: \(ipLocation.displayName) (IP 기반, 대략적 위치)"
            context += "\n위치 좌표: 위도 \(String(format: "%.4f", ipLocation.latitude)), 경도 \(String(format: "%.4f", ipLocation.longitude))"
        }
        
        return context
    }
    
    // MARK: - Llama 3.1 Chat Template
    
    /// Llama 3.1 공식 Chat Template 적용
    /// - Parameters:
    ///   - userMessage: 사용자 메시지
    ///   - searchResults: 웹 검색 결과 (선택적)
    ///   - previousTurns: 이전 대화 턴들 (질문+응답, 최대 2개)
    /// - Returns: 포맷된 전체 프롬프트
    private func formatChatPrompt(userMessage: String, searchResults: [SearchResult]? = nil, previousTurns: [ConversationTurn] = []) -> String {
        let bos = "<|begin_of_text|>"
        let startHeader = "<|start_header_id|>"
        let endHeader = "<|end_header_id|>"
        let eot = "<|eot_id|>"
        
        // 현재 컨텍스트 정보 추가
        let contextInfo = getCurrentContext()
        
        // 이전 대화 턴 정보 추가 (질문+응답)
        var previousTurnsContext = ""
        if !previousTurns.isEmpty {
            previousTurnsContext = "\n\n[이전 대화 맥락 - 참고용]\n"
            previousTurnsContext += "⚠️ 중요: 아래 대화는 참고용입니다. 이전 질문에 답변하지 마세요. 오직 현재 질문에만 답변하세요.\n\n"
            for (index, turn) in previousTurns.enumerated() {
                previousTurnsContext += "\(index + 1). 사용자: \(turn.userQuestion)\n"
                previousTurnsContext += "   응답: \(turn.aiResponse)\n"
            }
            previousTurnsContext += "\n⚠️ 위 대화는 맥락 이해를 위한 참고 자료일 뿐입니다. 반드시 아래 [사용자 질문]의 현재 질문에만 답변하세요."
        }
        
        // 검색 결과가 있으면 프롬프트에 포함
        var enhancedMessage = "[현재 상황 정보]\n\(contextInfo)\(previousTurnsContext)\n\n[사용자 질문] ⚠️ 반드시 이 질문에만 답변하세요\n\(userMessage)"
        
        if let results = searchResults, !results.isEmpty {
            var searchContext = "\n\n[참고 정보]\n"
            // 검색 결과를 최대 2개로 제한하고, 각 결과의 내용을 50자로 제한하여 토큰 수 절약
            let limitedResults = Array(results.prefix(2))
            for (index, result) in limitedResults.enumerated() {
                // 제목도 30자로 제한
                let title = String(result.title.prefix(30))
                let content = String(result.content.prefix(50))
                searchContext += "\(index + 1). \(title)\n"
                searchContext += "   \(content)\n"
            }
            searchContext += "\n위 정보를 바탕으로 사용자의 질문에 직접적으로 답변하세요. 정보를 나열하지 말고 자연스럽게 정리하여 답변하세요."
            enhancedMessage += searchContext
        } else {
            // 검색 결과가 없을 때 안내 추가
            enhancedMessage += "\n\n[안내]\n웹 검색 결과가 없습니다. 자신의 지식으로 답변하세요. 자신의 역할을 설명하지 말고 바로 질문에 답변하세요."
        }
        
        let formattedPrompt = """
\(bos)\(startHeader)system\(endHeader)

\(systemPrompt)\(eot)\(startHeader)user\(endHeader)

\(enhancedMessage)\(eot)\(startHeader)assistant\(endHeader)

"""
        
        return formattedPrompt
    }
    
    
    func loadModel() async {
        do {
            // 1. 저장된 모델 경로 확인
            if let savedPath = UserDefaults.standard.string(forKey: "selectedModelPath") {
                // print("💾 저장된 모델 경로 발견: \(savedPath)")
                
                if FileManager.default.fileExists(atPath: savedPath) {
                    // print("✅ 저장된 경로에 파일 존재 - 자동 로드 시도")
                    let success = await loadModelFromPath(savedPath)
                    
                    if success {
                        // print("✅ 저장된 모델 자동 로드 성공")
                        return
                    } else {
                        // print("⚠️ 저장된 모델 로드 실패 - 경로 제거")
                        UserDefaults.standard.removeObject(forKey: "selectedModelPath")
                    }
                } else {
                    // print("⚠️ 저장된 경로에 파일 없음 - 경로 제거")
                    UserDefaults.standard.removeObject(forKey: "selectedModelPath")
                }
            }
            
            // 2. 기본 경로에서 모델 찾기
            // print("🔍 기본 경로에서 모델 검색")
            let modelPath = try getModelPath()
            await loadModelFromPath(modelPath)
            
        } catch {
            isModelLoaded = false
            loadingProgress = "모델 파일을 선택해주세요"
            // print("ℹ️ 모델 파일 선택 필요")
        }
    }
    
    @discardableResult
    func loadModelFromPath(_ path: String) async -> Bool {
        do {
            loadingProgress = "모델 로딩 중..."
            // print("📂 모델 로드 시작: \(path)")
            
            // LlamaContext 생성 및 초기화
            llamaContext = LlamaContext(modelPath: path)
            try await llamaContext?.initialize()
            
            isModelLoaded = true
            loadingProgress = "모델 로드 완료"
            // print("✅ 모델이 성공적으로 로드되었습니다")
            
            // 성공 시 경로 저장
            UserDefaults.standard.set(path, forKey: "selectedModelPath")
            // print("💾 모델 경로 저장: \(path)")
            
            return true
            
        } catch {
            isModelLoaded = false
            loadingProgress = "모델 로드 실패: \(error.localizedDescription)"
            // print("❌ 모델 로드 실패: \(error)")
            
            return false
        }
    }
    
    private func getModelPath() throws -> String {
        // 프로젝트 루트에서 모델 파일 찾기 (개발 중)
        let projectPath = "/Volumes/Transcend/Projects/BanyaLLM/BanyaLLM/\(modelFilename)"
        if FileManager.default.fileExists(atPath: projectPath) {
            // print("📁 모델 경로: \(projectPath)")
            return projectPath
        }
        
        // Documents 디렉토리에서 찾기
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelPath = documentsPath.appendingPathComponent(modelFilename).path
        
        if FileManager.default.fileExists(atPath: modelPath) {
            // print("📁 모델 경로: \(modelPath)")
            return modelPath
        }
        
        // Bundle에서 모델 파일 찾기 (배포 시)
        if let path = Bundle.main.path(forResource: "llama31-banyaa-q4_k_m", ofType: "gguf") {
            // print("📁 모델 경로: \(path)")
            return path
        }
        
        // print("❌ 모델 파일을 찾을 수 없습니다")
        // print("다음 경로를 확인해주세요:")
        // print("1. \(projectPath)")
        // print("2. \(modelPath)")
        
        throw LlamaError.modelNotFound
    }
    
    func generate(prompt: String) async -> AsyncStream<String> {
        return AsyncStream { continuation in
            Task {
                // 인사 키워드 감지 및 즉시 응답
                let greetingKeywords = ["안녕", "안녕하세요", "하이", "헬로", "hello", "hi", "hey", "반가워", "반갑습니다"]
                let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                
                // 인사 키워드가 포함되어 있고, 질문이 아닌 경우 (인사만 있는 경우)
                let isGreeting = greetingKeywords.contains { keyword in
                    trimmedPrompt.contains(keyword.lowercased())
                } && !trimmedPrompt.contains("?") && !trimmedPrompt.contains("뭐") && !trimmedPrompt.contains("무엇")
                
                if isGreeting {
                    // 인사 응답 즉시 반환
                    let greetingResponse = "안녕하세요! 무엇을 도와드릴까요?"
                    continuation.yield(greetingResponse)
                    // 대화 히스토리에 저장
                    self.conversationHistory.saveTurn(userQuestion: prompt, aiResponse: greetingResponse)
                    continuation.finish()
                    return
                }
                
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
                        // print("❌ LlamaContext가 초기화되지 않았습니다")
                        continuation.yield("모델이 로드되지 않았습니다. 앱을 재시작해주세요.")
                        continuation.finish()
                        return
                    }
                    
                    // 네트워크 연결 상태 확인 및 웹 검색
                    var searchResults: [SearchResult]? = nil
                    let isConnected = self.checkNetworkConnection()
                    
                    if isConnected {
                        // 인터넷 연결되어 있으면 무조건 웹 검색
                        if let tavilyService = self.tavilyService {
                            // print("🔍 인터넷 연결됨: Tavily로 웹 검색 중...")
                            
                            do {
                                searchResults = try await tavilyService.search(query: prompt)
                                if let results = searchResults, !results.isEmpty {
                                    // print("✅ 검색 결과 \(results.count)개 발견")
                                } else {
                                    // print("⚠️ 검색 결과 없음")
                                }
                            } catch {
                                // print("❌ Tavily 검색 실패: \(error)")
                                // 검색 실패해도 LLM 응답은 계속 진행
                            }
                        } else {
                            // print("⚠️ Tavily API 키가 설정되지 않았습니다. LLM 자체 지식으로 답변합니다.")
                        }
                    } else {
                        // 인터넷 연결 안 됨: LLM 자체 지식으로 답변
                        // print("📴 인터넷 연결 안 됨: LLM 자체 지식으로 답변합니다.")
                    }
                    
                    // 대화 히스토리에서 이전 대화 턴 불러오기 (질문+응답)
                    let previousTurns = self.conversationHistory.getRecentTurns(count: 2)
                    
                    // Llama 3.1 Chat Template 적용 (검색 결과 및 이전 대화 포함)
                    let formattedPrompt = self.formatChatPrompt(userMessage: prompt, searchResults: searchResults, previousTurns: previousTurns)
                    
                    // 첫 번째 토큰이 도착하기 전까지 "..." 애니메이션 표시
                    class TokenReceivedFlag {
                        var value = false
                    }
                    let isFirstTokenReceived = TokenReceivedFlag()
                    let animationTask = Task {
                        // "..."를 깜빡이는 효과로 표시 (3개까지만 표시하고 반복)
                        while !isFirstTokenReceived.value && !Task.isCancelled {
                            // "..." 표시
                            continuation.yield("...")
                            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5초 표시
                            // "..." 지우기 (빈 문자열로 덮어쓰기)
                            continuation.yield("")
                            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2초 대기
                        }
                    }
                    
                    // LLM 추론 초기화
                    do {
                        try await llamaContext.completionInit(text: formattedPrompt)
                    } catch LlamaError.batchSizeExceeded {
                        // 배치 크기 초과 오류 발생 - 컨텍스트 초기화 및 대화 히스토리 삭제
                        await llamaContext.clear()  // 컨텍스트 상태 초기화
                        self.conversationHistory.clearHistory()  // 대화 히스토리 삭제
                        animationTask.cancel()
                        continuation.yield("메모리 초과로 대화가 중단 되었습니다. 다시 질문해 주세요.")
                        continuation.finish()
                        return
                    } catch {
                        // 기타 오류 - 컨텍스트 초기화
                        await llamaContext.clear()
                        animationTask.cancel()
                        continuation.yield("오류가 발생했습니다. 다시 시도해 주세요.")
                        continuation.finish()
                        return
                    }
                    
                    // 스트리밍 응답 생성 (강화된 특수 토큰 필터링)
                    var accumulatedRaw = ""
                    var previousCleanedLength = 0
                    var finalResponse = ""  // 최종 응답 저장용
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
                        var iterations = 0
                        while cleaned.count != previousLength && iterations < 10 {
                            previousLength = cleaned.count
                            for pattern in specialTokenPatterns {
                                cleaned = cleaned.replacingOccurrences(of: pattern, with: "")
                            }
                            iterations += 1
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
                        
                        // 3. 부분 특수 토큰 패턴 제거 (공격적 필터링)
                        // "<|" + "|>" 조합을 찾아 제거
                        var foundPattern = true
                        var patternIterations = 0
                        while foundPattern && patternIterations < 10 {  // 무한 루프 방지
                            patternIterations += 1
                            foundPattern = false
                            
                            // 방법 1: "<|" + "|>" 조합 찾기
                            if let startRange = cleaned.range(of: "<|", options: .backwards),
                               let endRange = cleaned.range(of: "|>", range: startRange.upperBound..<cleaned.endIndex) {
                                // 특수 토큰 패턴 발견: 제거
                                cleaned = String(cleaned[..<startRange.lowerBound]) + String(cleaned[endRange.upperBound...])
                                foundPattern = true
                                continue
                            }
                            
                            // 방법 2: 단독 파이프 제거 (특수 토큰의 일부일 가능성)
                            if cleaned.contains("|") && !cleaned.contains("<|") && !cleaned.contains("|>") {
                                // 단독 파이프가 있고 특수 토큰 패턴이 없으면 제거
                                cleaned = cleaned.replacingOccurrences(of: "|", with: "")
                                foundPattern = true
                            }
                            
                            // 방법 3: 정규식으로 부분 패턴 제거 (<|...|>)
                            if let regex = try? NSRegularExpression(pattern: "<\\|[^|]*\\|>", options: []) {
                                let range = NSRange(cleaned.startIndex..., in: cleaned)
                                let newCleaned = regex.stringByReplacingMatches(
                                    in: cleaned,
                                    options: [],
                                    range: range,
                                    withTemplate: ""
                                )
                                if newCleaned != cleaned {
                                    cleaned = newCleaned
                                    foundPattern = true
                                }
                            }
                            
                            // 방법 4: 공백 + "<|" 또는 "|>" + 공백 패턴 제거
                            cleaned = cleaned.replacingOccurrences(of: " <|", with: "")
                            cleaned = cleaned.replacingOccurrences(of: "<| ", with: "")
                            cleaned = cleaned.replacingOccurrences(of: " |>", with: "")
                            cleaned = cleaned.replacingOccurrences(of: "|> ", with: "")
                        }
                        
                        // 4. 이상한 패턴 제거 (<kts:1> 등)
                        if let regex = try? NSRegularExpression(pattern: "<[^>]*>", options: []) {
                            let range = NSRange(cleaned.startIndex..., in: cleaned)
                            cleaned = regex.stringByReplacingMatches(
                                in: cleaned,
                                options: [],
                                range: range,
                                withTemplate: ""
                            )
                        }
                        
                        // 5. 특수 문자 조합 제거 (^^ 등 불필요한 이모지)
                        cleaned = cleaned.replacingOccurrences(of: "^^", with: "")
                        cleaned = cleaned.replacingOccurrences(of: "^^^", with: "")
                        
                        return cleaned
                    }
                    
                    // 반복 감지 및 조기 종료
                    var lastSentences: [String] = []  // 최근 문장들 저장
                    var previousSentenceCount = 0
                    let maxSentenceHistory = 10  // 최근 10개 문장 저장 (더 많은 히스토리)
                    let similarityThreshold = 0.7  // 70% 이상 유사하면 반복으로 간주 (더 엄격)
                    var shouldStopAfterSentence = false  // 문장 완성 후 종료 플래그
                    var stopReason = ""  // 종료 이유
                    var textLengthWhenStopRequested = 0  // 종료 요청 시점의 텍스트 길이
                    
                    // 토큰 레벨 반복 감지
                    var lastTokens: [String] = []  // 최근 토큰들 저장 (최대 20개)
                    let maxTokenHistory = 20
                    let tokenRepeatThreshold = 5  // 같은 토큰이 5번 연속 반복되면 종료
                    
                    // 문장 유사도 계산 함수 (Jaccard 유사도 + Levenshtein 거리)
                    func calculateSimilarity(_ str1: String, _ str2: String) -> Double {
                        // 1. 완전 일치
                        if str1 == str2 {
                            return 1.0
                        }
                        
                        // 2. 단어 기반 Jaccard 유사도
                        let words1 = Set(str1.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
                        let words2 = Set(str2.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
                        
                        guard !words1.isEmpty && !words2.isEmpty else {
                            return 0.0
                        }
                        
                        let intersection = words1.intersection(words2)
                        let union = words1.union(words2)
                        let jaccardSimilarity = Double(intersection.count) / Double(union.count)
                        
                        // 3. 문자열 길이 기반 유사도 (짧은 문장이 긴 문장에 포함되는 경우)
                        let longer = str1.count > str2.count ? str1 : str2
                        let shorter = str1.count > str2.count ? str2 : str1
                        let containmentSimilarity = longer.contains(shorter) ? Double(shorter.count) / Double(longer.count) : 0.0
                        
                        // 4. 최대값 반환 (둘 중 하나라도 높으면 유사)
                        return max(jaccardSimilarity, containmentSimilarity)
                    }
                    
                    // 문장 완성 여부 확인 함수
                    func isSentenceComplete(_ text: String) -> Bool {
                        guard !text.isEmpty else { return false }
                        
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return false }
                        
                        // 마지막 문자가 종료 문자인지 확인
                        let lastChar = trimmed.last
                        if lastChar == "." || lastChar == "!" || lastChar == "?" {
                            // 마지막 문장이 완성되었는지 확인
                            // 숫자+마침표 패턴(예: "1.", "2.")은 제외
                            let lastSentence = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).last?.trimmingCharacters(in: .whitespaces) ?? ""
                            
                            // 숫자만 있는 문장이면 미완성으로 간주
                            if lastSentence.range(of: "^\\d+\\.?$", options: .regularExpression) != nil {
                                return false
                            }
                            
                            // 마지막 문장이 종료 문자로 끝나면 완성된 것으로 간주
                            return true
                        }
                        
                        return false
                    }
                    
                    while await !llamaContext.isDone {
                        let token: String
                        do {
                            token = try await llamaContext.completionLoop()
                        } catch LlamaError.batchSizeExceeded {
                            // 배치 크기 초과 오류 발생 - 컨텍스트 초기화 및 대화 히스토리 삭제
                            if !isFirstTokenReceived.value {
                                isFirstTokenReceived.value = true
                                animationTask.cancel()
                            }
                            await llamaContext.clear()  // 컨텍스트 상태 초기화
                            self.conversationHistory.clearHistory()  // 대화 히스토리 삭제
                            continuation.yield("메모리 초과로 대화가 중단 되었습니다. 다시 질문해 주세요.")
                            continuation.finish()
                            return
                        } catch {
                            // 기타 오류 - 계속 진행
                            continue
                        }
                        
                        if !token.isEmpty {
                            // 첫 번째 토큰 도착 - 애니메이션 중지
                            if !isFirstTokenReceived.value {
                                isFirstTokenReceived.value = true
                                animationTask.cancel()
                                // 빈 문자열을 yield하지 않고, cleanedText가 준비되면 바로 yield
                                // 이렇게 하면 첫 글자가 잘리지 않음
                            }
                            
                            // 토큰 레벨 반복 감지 (문장 완성 전에 감지)
                            let trimmedToken = token.trimmingCharacters(in: .whitespaces)
                            if !trimmedToken.isEmpty {
                                // 숫자만 있는 토큰은 반복 감지에서 제외 (예: "1", "2", "3" 등)
                                let isNumericOnly = trimmedToken.range(of: "^\\d+$", options: .regularExpression) != nil
                                
                                if !isNumericOnly {
                                    lastTokens.append(trimmedToken)
                                    if lastTokens.count > maxTokenHistory {
                                        lastTokens.removeFirst()
                                    }
                                    
                                    // 같은 토큰이 연속으로 반복되는지 확인
                                    if lastTokens.count >= tokenRepeatThreshold {
                                        let recentTokens = Array(lastTokens.suffix(tokenRepeatThreshold))
                                        let firstToken = recentTokens[0]
                                        let allSame = recentTokens.allSatisfy { $0 == firstToken }
                                        
                                        if allSame && firstToken.count > 0 {
                                            // 같은 토큰이 연속 반복됨 - 문장 완성 여부 확인 후 종료
                                            let currentText = filterSpecialTokens(accumulatedRaw)
                                            if isSentenceComplete(currentText) {
                                                finalResponse = currentText
                                                await llamaContext.forceStop()
                                                await llamaContext.clear()
                                                self.conversationHistory.saveTurn(userQuestion: prompt, aiResponse: finalResponse)
                                                continuation.finish()
                                                return
                                            }
                                            // 미완성 문장이면 계속 진행
                                        }
                                    }
                                }
                            }
                            
                            accumulatedRaw += token
                            
                            // 강화된 특수 토큰 필터링
                            var cleanedText = filterSpecialTokens(accumulatedRaw)
                            
                            // 반복 감지: 문장 단위로 체크
                            // 숫자 목록 패턴 (예: "1. 2. 3.")을 고려하여 문장 분리
                            let sentences = cleanedText.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { sentence in
                                    // 빈 문장 제외
                                    guard !sentence.isEmpty && sentence.count > 3 else { return false }
                                    let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                                    
                                    // 숫자만 있는 문장은 제외하되, 숫자 목록 패턴의 일부인 경우는 허용
                                    // 예: "1. 첫 번째 항목"은 허용, "1."만 있는 것은 제외
                                    // 숫자 + 마침표 + 공백 + 텍스트 패턴은 허용
                                    if trimmed.range(of: "^\\d+\\.\\s+", options: .regularExpression) != nil {
                                        // "1. " 패턴으로 시작하는 경우는 허용 (목록 항목)
                                        return true
                                    }
                                    
                                    // 숫자만 있거나 숫자+마침표만 있는 경우 제외
                                    if trimmed.range(of: "^\\d+\\.?$", options: .regularExpression) != nil {
                                        return false
                                    }
                                    
                                    return true
                                }
                            
                            // 새 문장이 추가되었는지 확인
                            if sentences.count > previousSentenceCount {
                                let newSentences = Array(sentences.suffix(sentences.count - previousSentenceCount))
                                
                                for newSentence in newSentences {
                                    // 유사도 기반 반복 감지
                                    var isRepeated = false
                                    var mostSimilar: (sentence: String, similarity: Double)?
                                    
                                    for previousSentence in lastSentences {
                                        let similarity = calculateSimilarity(newSentence, previousSentence)
                                        
                                        if similarity >= similarityThreshold {
                                            isRepeated = true
                                            mostSimilar = (previousSentence, similarity)
                                            break
                                        }
                                        
                                        // 가장 유사한 문장 추적 (디버깅용)
                                        if mostSimilar == nil || similarity > mostSimilar!.similarity {
                                            mostSimilar = (previousSentence, similarity)
                                        }
                                    }
                                    
                                    if isRepeated {
                                        // let similarityPercent = Int((mostSimilar!.similarity * 100))
                                        // print("🛑 반복 감지: 유사도 \(similarityPercent)% - 문장 완성 확인 후 종료")
                                        // print("   현재: '\(newSentence.prefix(40))...'")
                                        // print("   이전: '\(mostSimilar!.sentence.prefix(40))...'")
                                        
                                        // 반복 감지 시 문장 완성 여부 확인 후 종료
                                        if isSentenceComplete(cleanedText) {
                                            finalResponse = cleanedText
                                            await llamaContext.forceStop()
                                            await llamaContext.clear()
                                            self.conversationHistory.saveTurn(userQuestion: prompt, aiResponse: finalResponse)
                                            continuation.finish()
                                            return
                                        }
                                        // 미완성 문장이면 계속 진행 (반복이지만 문장을 완성해야 함)
                                    }
                                    
                                    // 문장 히스토리에 추가
                                    lastSentences.append(newSentence)
                                    if lastSentences.count > maxSentenceHistory {
                                        lastSentences.removeFirst()
                                    }
                                }
                                
                                previousSentenceCount = sentences.count
                            }
                            
                            // 문장 종료 후 추가 생성 방지 (5-6문장 후 종료)
                            if !shouldStopAfterSentence && sentences.count >= 6 {
                                // 문장 완성 여부 확인 후 종료
                                if isSentenceComplete(cleanedText) {
                                    // print("✅ 충분한 응답 생성: 조기 종료")
                                    finalResponse = cleanedText
                                    await llamaContext.forceStop()
                                    await llamaContext.clear()
                                    self.conversationHistory.saveTurn(userQuestion: prompt, aiResponse: finalResponse)
                                    continuation.finish()
                                    return
                                }
                            }
                            
                            // 반복 감지 후 문장 완성 대기 (더 짧은 대기 시간)
                            if shouldStopAfterSentence {
                                // 문장 완성 여부 확인 후 종료
                                if isSentenceComplete(cleanedText) {
                                    // print("✅ 문장 완성됨: \(stopReason)로 종료")
                                    finalResponse = cleanedText
                                    await llamaContext.forceStop()
                                    await llamaContext.clear()
                                    self.conversationHistory.saveTurn(userQuestion: prompt, aiResponse: finalResponse)
                                    continuation.finish()
                                    return
                                }
                                
                                // 최대 대기 토큰 수 체크 (문장 완성을 기다리는 동안 너무 많은 토큰 생성 방지)
                                // 30자로 줄여서 문장이 잘리기 전에 빠르게 종료
                                let textGrowth = cleanedText.count - textLengthWhenStopRequested
                                if textGrowth > 30 {  // 대략 10-15토큰 정도 (한국어 기준)
                                    // 문장 완성 여부 확인 후 종료 (미완성이어도 너무 오래 기다렸으면 종료)
                                    // let lastWords = cleanedText.suffix(20).trimmingCharacters(in: .whitespaces)
                                    // if !lastWords.isEmpty {
                                    //     print("⚠️ 문장 완성 대기 시간 초과: 자연스러운 종료 지점에서 종료 (텍스트 증가: \(textGrowth)자)")
                                    // } else {
                                    //     print("⚠️ 문장 완성 대기 시간 초과: 강제 종료 (텍스트 증가: \(textGrowth)자)")
                                    // }
                                    // 문장이 완성되었거나, 완성되지 않았어도 너무 오래 기다렸으면 종료
                                    if isSentenceComplete(cleanedText) || textGrowth > 100 {
                                        finalResponse = cleanedText
                                        await llamaContext.forceStop()
                                        await llamaContext.clear()
                                        self.conversationHistory.saveTurn(userQuestion: prompt, aiResponse: finalResponse)
                                        continuation.finish()
                                        return
                                    }
                                    // 미완성이지만 아직 기다릴 수 있으면 계속 진행
                                }
                            }
                            
                            // 이전에 출력한 부분을 제외하고 새로운 부분만 출력
                            if cleanedText.count > previousCleanedLength {
                                let newContent = String(cleanedText.dropFirst(previousCleanedLength))
                                if !newContent.isEmpty {
                                    // 첫 번째 토큰인 경우: 빈 문자열을 먼저 yield하여 "..."를 지우고, 그 다음 전체 텍스트를 yield
                                    if previousCleanedLength == 0 && isFirstTokenReceived.value {
                                        // "..."를 지우기 위해 빈 문자열 yield
                                        continuation.yield("")
                                        // 약간의 딜레이 후 전체 텍스트 yield (첫 글자가 잘리지 않도록)
                                        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05초 딜레이
                                        continuation.yield(cleanedText)
                                        previousCleanedLength = cleanedText.count
                                    } else {
                                        continuation.yield(newContent)
                                        previousCleanedLength = cleanedText.count
                                    }
                                    finalResponse = cleanedText  // 최종 응답 업데이트
                                }
                            } else if cleanedText.count < previousCleanedLength {
                                // 필터링으로 인해 텍스트가 줄어든 경우 (특수 토큰 제거됨)
                                previousCleanedLength = cleanedText.count
                            }
                            
                            // 자연스러운 타이핑 효과
                            try? await Task.sleep(nanoseconds: 50_000_000)
                        }
                    }
                    
                    // 추론 완료 후 정리 및 대화 히스토리 저장
                    // 애니메이션 중지 (아직 실행 중이면)
                    if !isFirstTokenReceived.value {
                        isFirstTokenReceived.value = true
                        animationTask.cancel()
                    }
                    
                    await llamaContext.clear()
                    
                    // 최종 응답이 있으면 대화 히스토리에 저장
                    if !finalResponse.isEmpty {
                        self.conversationHistory.saveTurn(userQuestion: prompt, aiResponse: finalResponse)
                    }
                    
                    continuation.finish()
                #endif
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LlamaManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            Task { @MainActor in
                self.currentLocation = location
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // print("❌ 위치 정보 가져오기 실패: \(error.localizedDescription)")
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}

