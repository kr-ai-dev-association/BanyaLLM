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
    
    // Llama 3.1 System Prompt (청소년 일상 지원 에이전트)
    private let systemPrompt = """
너는 청소년의 일상생활을 돕는 친절한 에이전트다. 말은 간단하고 짧게 한다. 한 번에 한 단계씩 안내한다. 위급한 상황이라고 판단될 경우 즉시 보호자나 119에 연락하도록 안내한다. 복잡한 요청은 다시 확인하고 필요한 정보를 먼저 묻는다. 일정 관리, 준비물 체크, 이동 안내, 감정 조절 도움, 사회적 상황 대처 연습을 친절하고 나이스하게 돕는게 너의 제일 큰 역할이야. 물결표와 이모티콘, 과도한 문장부호(!!!, .. 등)는 사용하지 않는다. 문장부호는 최대 1개만 사용한다. 그리고 최대한 친절하게 대답하고 친근하게 대답해.

절대 금지: 사용자에게 "발달장애인"이라는 단어나 "장애인"과 유사한 표현을 절대 사용하지 않는다. 사용자의 특정 상황이나 조건을 명시적으로 언급하지 않는다. 대신 모든 사용자를 존중하고 친절하게 대하는 일반적인 일상 지원 에이전트처럼 행동한다.

중요: 사용자가 제공하는 현재 날짜, 시간, 위치 정보는 내부적으로만 활용하고, 절대 사용자에게 명시적으로 언급하거나 출력하지 않는다. 예를 들어 "현재 날짜는 2025년 11월 13일입니다" 같은 식으로 말하지 않는다. 대신 이 정보를 활용하여 질문에 자연스럽게 답변한다.

웹 검색 결과가 제공되면, 반드시 그 결과를 기반으로 사용자의 질문에 맞게 내용을 재조립하여 답변해야 한다. 검색 결과의 정보를 그대로 나열하지 말고, 사용자의 질의에 맞게 자연스럽게 재구성하여 제공한다. 웹 검색 결과가 없거나 인터넷이 연결되지 않은 경우에만 자신의 지식으로 답변한다.
"""
    
    // Tavily API 키 설정 (환경 변수나 설정에서 가져올 수 있음)
    func setTavilyAPIKey(_ apiKey: String) {
        self.tavilyService = TavilyService(apiKey: apiKey)
        print("✅ Tavily API 키 설정 완료")
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
                print("🌐 네트워크 상태: \(path.status == .satisfied ? "연결됨" : "연결 안 됨")")
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
        print("🌐 IP 기반 위치 정보 가져오기 시도...")
        ipLocation = await ipLocationService.getLocationFromIP()
        print("✅ IP 기반 위치 정보 획득: \(ipLocation.displayName)")
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
                print("✅ 현재 위치 정보 획득 완료")
            } else {
                print("⚠️ 위치 정보를 가져올 수 없습니다")
            }
        } else {
            print("⚠️ 위치 권한이 없습니다. 날짜/시간 정보만 제공됩니다.")
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
    ///   - previousQuestions: 이전 질문들 (최대 2개)
    /// - Returns: 포맷된 전체 프롬프트
    private func formatChatPrompt(userMessage: String, searchResults: [SearchResult]? = nil, previousQuestions: [String] = []) -> String {
        let bos = "<|begin_of_text|>"
        let startHeader = "<|start_header_id|>"
        let endHeader = "<|end_header_id|>"
        let eot = "<|eot_id|>"
        
        // 현재 컨텍스트 정보 추가
        let contextInfo = getCurrentContext()
        
        // 이전 질문 정보 추가
        var previousQuestionsContext = ""
        if !previousQuestions.isEmpty {
            previousQuestionsContext = "\n\n[이전 대화 맥락]\n"
            for (index, question) in previousQuestions.enumerated() {
                previousQuestionsContext += "\(index + 1). \(question)\n"
            }
            previousQuestionsContext += "\n위 질문들을 참고하여 현재 질문에 답변해주세요."
        }
        
        // 검색 결과가 있으면 프롬프트에 포함
        var enhancedMessage = "[현재 상황 정보]\n\(contextInfo)\(previousQuestionsContext)\n\n[사용자 질문]\n\(userMessage)"
        
        if let results = searchResults, !results.isEmpty {
            var searchContext = "\n\n[웹 검색 결과]\n"
            // 검색 결과를 최대 3개로 제한하고, 각 결과의 내용을 100자로 제한하여 토큰 수 절약
            let limitedResults = Array(results.prefix(3))
            for (index, result) in limitedResults.enumerated() {
                searchContext += "\(index + 1). \(result.title)\n"
                searchContext += "   \(result.content.prefix(100))\n"
            }
            searchContext += "\n위 검색 결과를 참고하여 질문에 답변해주세요."
            enhancedMessage += searchContext
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
    
    func generate(prompt: String, previousQuestions: [String] = []) async -> AsyncStream<String> {
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
                    
                    // 네트워크 연결 상태 확인 및 웹 검색
                    var searchResults: [SearchResult]? = nil
                    let isConnected = self.checkNetworkConnection()
                    
                    if isConnected {
                        // 인터넷 연결되어 있으면 무조건 웹 검색
                        if let tavilyService = self.tavilyService {
                            print("🔍 인터넷 연결됨: Tavily로 웹 검색 중...")
                            continuation.yield("생각 중... ")
                            
                            do {
                                searchResults = try await tavilyService.search(query: prompt)
                                if let results = searchResults, !results.isEmpty {
                                    print("✅ 검색 결과 \(results.count)개 발견")
                                } else {
                                    print("⚠️ 검색 결과 없음")
                                }
                            } catch {
                                print("❌ Tavily 검색 실패: \(error)")
                                // 검색 실패해도 LLM 응답은 계속 진행
                            }
                        } else {
                            print("⚠️ Tavily API 키가 설정되지 않았습니다. LLM 자체 지식으로 답변합니다.")
                        }
                    } else {
                        // 인터넷 연결 안 됨: LLM 자체 지식으로 답변
                        print("📴 인터넷 연결 안 됨: LLM 자체 지식으로 답변합니다.")
                    }
                    
                    // Llama 3.1 Chat Template 적용 (검색 결과 및 이전 질문 포함)
                    let formattedPrompt = self.formatChatPrompt(userMessage: prompt, searchResults: searchResults, previousQuestions: previousQuestions)
                    
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
                    
                    while await !llamaContext.isDone {
                        let token = await llamaContext.completionLoop()
                        
                        if !token.isEmpty {
                            accumulatedRaw += token
                            
                            // 강화된 특수 토큰 필터링
                            var cleanedText = filterSpecialTokens(accumulatedRaw)
                            
                            // 반복 감지: 문장 단위로 체크
                            let sentences = cleanedText.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty && $0.count > 3 }  // 3자 이상인 문장 체크 (더 민감하게)
                            
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
                                        let similarityPercent = Int((mostSimilar!.similarity * 100))
                                        print("🛑 반복 감지: 유사도 \(similarityPercent)% - 즉시 종료")
                                        print("   현재: '\(newSentence.prefix(40))...'")
                                        print("   이전: '\(mostSimilar!.sentence.prefix(40))...'")
                                        
                                        // 반복 감지 시 즉시 종료 (문장 완성 대기 없음)
                                        await llamaContext.forceStop()
                                        await llamaContext.clear()
                                        continuation.finish()
                                        return
                                    }
                                    
                                    // 문장 히스토리에 추가
                                    lastSentences.append(newSentence)
                                    if lastSentences.count > maxSentenceHistory {
                                        lastSentences.removeFirst()
                                    }
                                }
                                
                                previousSentenceCount = sentences.count
                            }
                            
                            // 문장 종료 후 추가 생성 방지 (2-3문장 후 종료)
                            if !shouldStopAfterSentence && sentences.count >= 3 {
                                let lastChar = cleanedText.last
                                if lastChar == "." || lastChar == "!" || lastChar == "?" {
                                    print("✅ 충분한 응답 생성: 조기 종료")
                                    // 종료 문자 확인 직후 즉시 종료 (문장이 잘리지 않도록)
                                    await llamaContext.forceStop()
                                    await llamaContext.clear()
                                    continuation.finish()
                                    return
                                }
                            }
                            
                            // 반복 감지 후 문장 완성 대기 (더 짧은 대기 시간)
                            if shouldStopAfterSentence {
                                let lastChar = cleanedText.last
                                if lastChar == "." || lastChar == "!" || lastChar == "?" {
                                    print("✅ 문장 완성됨: \(stopReason)로 종료")
                                    await llamaContext.forceStop()
                                    await llamaContext.clear()
                                    continuation.finish()
                                    return
                                }
                                
                                // 최대 대기 토큰 수 체크 (문장 완성을 기다리는 동안 너무 많은 토큰 생성 방지)
                                // 30자로 줄여서 문장이 잘리기 전에 빠르게 종료
                                let textGrowth = cleanedText.count - textLengthWhenStopRequested
                                if textGrowth > 30 {  // 대략 10-15토큰 정도 (한국어 기준)
                                    // 문장이 완성되지 않았지만 더 이상 기다리지 않고 종료
                                    // 마지막 문장의 마지막 단어를 확인하여 자연스러운 종료 지점 찾기
                                    let lastWords = cleanedText.suffix(20).trimmingCharacters(in: .whitespaces)
                                    if !lastWords.isEmpty {
                                        print("⚠️ 문장 완성 대기 시간 초과: 자연스러운 종료 지점에서 종료 (텍스트 증가: \(textGrowth)자)")
                                    } else {
                                        print("⚠️ 문장 완성 대기 시간 초과: 강제 종료 (텍스트 증가: \(textGrowth)자)")
                                    }
                                    await llamaContext.forceStop()
                                    await llamaContext.clear()
                                    continuation.finish()
                                    return
                                }
                            }
                            
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
        print("❌ 위치 정보 가져오기 실패: \(error.localizedDescription)")
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}

