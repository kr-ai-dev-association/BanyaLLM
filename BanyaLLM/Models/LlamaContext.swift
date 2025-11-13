//
//  LlamaContext.swift
//  BanyaLLM
//
//  Created by Tony-M4 on 11/13/25.
//

import Foundation

enum LlamaError: Error {
    case couldNotInitializeContext
    case modelNotFound
    case failedToLoadModel
}

// Helper functions for llama_batch
func llama_batch_clear(_ batch: inout llama_batch) {
    batch.n_tokens = 0
}

func llama_batch_add(_ batch: inout llama_batch, _ id: llama_token, _ pos: llama_pos, _ seq_ids: [llama_seq_id], _ logits: Bool) {
    let tokenIndex = Int(batch.n_tokens)
    batch.token[tokenIndex] = id
    batch.pos[tokenIndex] = pos
    batch.n_seq_id[tokenIndex] = Int32(seq_ids.count)
    
    // seq_id 배열이 nil이 아닌지 확인하고 값 할당
    if let seqIdArray = batch.seq_id[tokenIndex] {
        for i in 0..<seq_ids.count {
            seqIdArray[i] = seq_ids[i]
        }
    } else {
        print("⚠️ seq_id 배열이 nil입니다. 토큰 인덱스: \(tokenIndex)")
    }
    
    batch.logits[tokenIndex] = logits ? 1 : 0
    batch.n_tokens += 1
}

actor LlamaContext {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var sampling: UnsafeMutablePointer<llama_sampler>?
    private var batch: llama_batch
    private var tokens_list: [llama_token] = []
    private var temporary_invalid_cchars: [CChar] = []
    
    var isDone: Bool = false
    var n_len: Int32 = 64   // 최대 생성 토큰 수 (매우 간결한 응답, 2-3문장)
    var n_cur: Int32 = 0
    
    // 강제 종료 메서드
    func forceStop() {
        isDone = true
    }
    var n_decode: Int32 = 0
    
    private let modelPath: String
    
    init(modelPath: String) {
        self.modelPath = modelPath
        // batch 크기를 2048로 늘려서 긴 프롬프트 처리 가능하도록 함
        self.batch = llama_batch_init(2048, 0, 1)
    }
    
    func initialize() throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            print("❌ 모델 파일을 찾을 수 없습니다: \(modelPath)")
            throw LlamaError.modelNotFound
        }
        
        print("✅ 모델 파일 확인: \(modelPath)")
        print("🔄 llama.cpp로 모델 로딩 중...")
        
        // llama.cpp 초기화
        llama_backend_init()
        
        var model_params = llama_model_default_params()
        
        #if targetEnvironment(simulator)
        model_params.n_gpu_layers = 0
        print("📱 시뮬레이터: CPU 모드")
        #else
        // GPU 메모리 부족 방지: 일부 레이어만 GPU에 로드
        model_params.n_gpu_layers = 24  // 33개 중 24개만 GPU (약 70%)
        print("⚡ 실제 기기: 하이브리드 모드 (GPU: 24레이어, CPU: 9레이어)")
        #endif
        
        guard let loadedModel = llama_model_load_from_file(modelPath, model_params) else {
            print("❌ 모델 로드 실패")
            throw LlamaError.couldNotInitializeContext
        }
        self.model = loadedModel
        
        let n_threads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        print("🧵 스레드 수: \(n_threads)")
        
        var ctx_params = llama_context_default_params()
        ctx_params.n_ctx = 1024  // 2048 → 1024로 줄여서 메모리 절약
        ctx_params.n_threads = Int32(n_threads)
        ctx_params.n_threads_batch = Int32(n_threads)
        
        print("🎛️ 컨텍스트 크기: 1024 (메모리 최적화)")
        
        guard let loadedContext = llama_init_from_model(loadedModel, ctx_params) else {
            print("❌ 컨텍스트 초기화 실패")
            throw LlamaError.couldNotInitializeContext
        }
        self.context = loadedContext
        
        // Sampling 초기화 (Llama 3.1 최적화)
        let sparams = llama_sampler_chain_default_params()
        self.sampling = llama_sampler_chain_init(sparams)
        
        // 1. Top-K 샘플링 (0 = 비활성화, Llama 3.1 권장)
        llama_sampler_chain_add(self.sampling, llama_sampler_init_top_k(0))
        
        // 2. Top-P (Nucleus Sampling) - 0.9
        llama_sampler_chain_add(self.sampling, llama_sampler_init_top_p(0.9, 1))
        
        // 3. Min-P - 낮은 확률 토큰 배제 (Llama 3.1 핵심 설정)
        llama_sampler_chain_add(self.sampling, llama_sampler_init_min_p(0.05, 1))
        
        // 4. Temperature - 창의성 조절 (0.6 = 더 결정론적, 반복 감소)
        llama_sampler_chain_add(self.sampling, llama_sampler_init_temp(0.6))
        
        // 5. Repeat Penalty - 반복 방지 강화 (1.15 = 강한 패널티, last_n=64 = 최근 64 토큰만 고려)
        llama_sampler_chain_add(self.sampling, llama_sampler_init_penalties(
            64,     // last_n: 최근 64 토큰만 고려 (반복 감지 정확도 향상)
            1.15,   // repeat_penalty: 강한 반복 패널티 (1.05 → 1.15)
            0.1,    // freq_penalty: 빈도 패널티 추가 (반복 단어 억제)
            0.1     // presence_penalty: 존재 패널티 추가 (이미 나온 단어 억제)
        ))
        
        // 6. Dist 샘플링 (최종 토큰 선택)
        llama_sampler_chain_add(self.sampling, llama_sampler_init_dist(UInt32.random(in: 0...1000)))
        
        print("🎛️ 샘플링 설정: Temp=0.6, Top-P=0.9, Min-P=0.05, Repeat=1.15 (last_n=64), Freq=0.1, Presence=0.1")
        
        self.vocab = llama_model_get_vocab(loadedModel)
        
        print("✅ llama.cpp 모델 로드 완료!")
    }
    
    func completionInit(text: String) {
        print("🚀 추론 시작")
        
        guard let context = context else { 
            print("❌ context가 nil입니다!")
            return 
        }
        
        tokens_list = tokenize(text: text, add_bos: true)
        temporary_invalid_cchars = []
        
        print("🔢 토큰화: \(tokens_list.count)개")
        
        let n_ctx = llama_n_ctx(context)
        let n_kv_req = tokens_list.count + (Int(n_len) - tokens_list.count)
        
        
        if n_kv_req > n_ctx {
            print("⚠️ 경고: n_kv_req > n_ctx")
        }
        
        llama_batch_clear(&batch)
        
        // batch 크기 제한 확인 (2048)
        let maxBatchSize = 2048
        if tokens_list.count > maxBatchSize {
            print("⚠️ 경고: 토큰 수(\(tokens_list.count))가 batch 크기(\(maxBatchSize))를 초과합니다. 처음 \(maxBatchSize)개만 사용합니다.")
        }
        
        // batch에 토큰 추가 (최대 batch 크기까지만)
        let tokensToAdd = min(tokens_list.count, maxBatchSize)
        for i in 0..<tokensToAdd {
            // seq_id 배열 nil 체크
            let seqIdArray = batch.seq_id[Int(batch.n_tokens)]
            if seqIdArray != nil {
                llama_batch_add(&batch, tokens_list[i], Int32(i), [0], false)
            } else {
                print("⚠️ seq_id 배열이 nil입니다. 토큰 인덱스: \(i) - batch 크기 초과 가능성")
                break
            }
        }
        
        if batch.n_tokens > 0 {
            batch.logits[Int(batch.n_tokens) - 1] = 1
            
            if llama_decode(context, batch) != 0 {
                print("❌ llama_decode() 실패")
            }
        } else {
            print("❌ batch에 토큰이 없습니다!")
        }
        
        n_cur = batch.n_tokens
        isDone = false
    }
    
    func completionLoop() -> String {
        guard let context = context,
              let sampling = sampling,
              let vocab = vocab else {
            isDone = true
            return ""
        }
        
        let new_token_id = llama_sampler_sample(sampling, context, batch.n_tokens - 1)
        
        // EOG 토큰 감지 (Llama 3.1 EOG 토큰 ID 직접 비교)
        // 128001: <|end_of_text|>, 128008: <|eom_id|>, 128009: <|eot_id|>
        let isEOG = (new_token_id == 128001 || new_token_id == 128008 || new_token_id == 128009)
        
        if isEOG || n_cur == n_len {
            print("✅ 생성 완료 (EOG: \(isEOG), 토큰: \(n_cur)개)")
            isDone = true
            temporary_invalid_cchars.removeAll()
            return "" // EOG 토큰은 출력하지 않음
        }
        
        // 특수 토큰 필터링 (Llama 3.1 특수 토큰은 출력하지 않음)
        // 128000-128255: 모든 특수 토큰 범위
        if new_token_id >= 128000 {
            // 특수 토큰은 배치에 추가하지만 출력하지 않음
            llama_batch_clear(&batch)
            llama_batch_add(&batch, new_token_id, n_cur, [0], true)
            
            n_decode += 1
            n_cur += 1
            
            if llama_decode(context, batch) != 0 {
                print("❌ llama_decode 실패!")
            }
            
            return "" // 빈 문자열 반환 (특수 토큰은 출력 안 함)
        }
        
        let new_token_cchars = token_to_piece(token: new_token_id)
        temporary_invalid_cchars.append(contentsOf: new_token_cchars)
        var new_token_str: String
        if let string = String(validatingUTF8: temporary_invalid_cchars + [0]) {
            temporary_invalid_cchars.removeAll()
            new_token_str = string
        } else if (0..<temporary_invalid_cchars.count).contains(where: {
            $0 != 0 && String(validatingUTF8: Array(temporary_invalid_cchars.suffix($0)) + [0]) != nil
        }) {
            let string = String(cString: temporary_invalid_cchars + [0])
            temporary_invalid_cchars.removeAll()
            new_token_str = string
        } else {
            new_token_str = ""
        }
        
        // Llama 3.1 특수 토큰 문자열 필터링
        // 모델이 일반 토큰으로 특수 토큰 문자열을 생성할 수 있음
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
        
        for pattern in specialTokenPatterns {
            new_token_str = new_token_str.replacingOccurrences(of: pattern, with: "")
        }
        
        // reserved_special_token 패턴 제거 (정규식 사용)
        if let regex = try? NSRegularExpression(pattern: "<\\|reserved_special_token_\\d+\\|>", options: []) {
            let range = NSRange(new_token_str.startIndex..., in: new_token_str)
            new_token_str = regex.stringByReplacingMatches(
                in: new_token_str,
                options: [],
                range: range,
                withTemplate: ""
            )
        }
        
        // 부분 특수 토큰 패턴 필터링 (토큰이 분해되어 생성되는 경우)
        // 예: '<|', '|>', 단독 '|' 등
        let partialPatterns = [
            "<|",  // 특수 토큰 시작
            "|>",  // 특수 토큰 끝
            "^\\|$",  // 단독 파이프 (정규식)
            "^<\\|",  // '<|'로 시작
            "\\|>$"   // '|>'로 끝
        ]
        
        // 단독 파이프 제거
        if new_token_str == "|" {
            new_token_str = ""
        }
        
        // '<|' 또는 '|>' 포함 시 제거
        if new_token_str.contains("<|") || new_token_str.contains("|>") {
            new_token_str = new_token_str.replacingOccurrences(of: "<|", with: "")
            new_token_str = new_token_str.replacingOccurrences(of: "|>", with: "")
        }
        
        // 정규식으로 부분 패턴 제거
        if let regex = try? NSRegularExpression(pattern: "<\\|.*?\\|>", options: []) {
            let range = NSRange(new_token_str.startIndex..., in: new_token_str)
            new_token_str = regex.stringByReplacingMatches(
                in: new_token_str,
                options: [],
                range: range,
                withTemplate: ""
            )
        }
        
        llama_batch_clear(&batch)
        llama_batch_add(&batch, new_token_id, n_cur, [0], true)
        
        n_decode += 1
        n_cur += 1
        
        if llama_decode(context, batch) != 0 {
            print("❌ llama_decode 실패!")
        }
        
        // 생성된 토큰 로그 출력 (디버깅용)
        if !new_token_str.isEmpty {
            print("🔤 토큰 출력: '\(new_token_str)' (ID: \(new_token_id))")
        }
        
        return new_token_str
    }
    
    func clear() {
        guard let context = context else { return }
        
        tokens_list.removeAll()
        temporary_invalid_cchars.removeAll()
        llama_memory_clear(llama_get_memory(context), true)
        n_cur = 0
        n_decode = 0
        isDone = false
    }
    
    func modelInfo() -> String {
        guard let model = model else {
            return "모델 미로드"
        }
        
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: 256)
        result.initialize(repeating: Int8(0), count: 256)
        defer {
            result.deallocate()
        }
        
        let nChars = llama_model_desc(model, result, 256)
        let bufferPointer = UnsafeBufferPointer(start: result, count: Int(nChars))
        
        var swiftString = ""
        for char in bufferPointer {
            swiftString.append(Character(UnicodeScalar(UInt8(char))))
        }
        
        return swiftString
    }
    
    private func tokenize(text: String, add_bos: Bool) -> [llama_token] {
        guard let vocab = vocab else { return [] }
        
        let utf8Count = text.utf8.count
        let n_tokens = utf8Count + (add_bos ? 1 : 0) + 1
        let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: n_tokens)
        let tokenCount = llama_tokenize(vocab, text, Int32(utf8Count), tokens, Int32(n_tokens), add_bos, false)
        
        var swiftTokens: [llama_token] = []
        for i in 0..<tokenCount {
            swiftTokens.append(tokens[Int(i)])
        }
        
        tokens.deallocate()
        
        return swiftTokens
    }
    
    private func token_to_piece(token: llama_token) -> [CChar] {
        guard let vocab = vocab else { return [] }
        
        let result = UnsafeMutablePointer<Int8>.allocate(capacity: 8)
        result.initialize(repeating: Int8(0), count: 8)
        defer {
            result.deallocate()
        }
        let nTokens = llama_token_to_piece(vocab, token, result, 8, 0, false)
        
        if nTokens < 0 {
            let newResult = UnsafeMutablePointer<Int8>.allocate(capacity: Int(-nTokens))
            newResult.initialize(repeating: Int8(0), count: Int(-nTokens))
            defer {
                newResult.deallocate()
            }
            let nNewTokens = llama_token_to_piece(vocab, token, newResult, -nTokens, 0, false)
            let bufferPointer = UnsafeBufferPointer(start: newResult, count: Int(nNewTokens))
            return Array(bufferPointer)
        } else {
            let bufferPointer = UnsafeBufferPointer(start: result, count: Int(nTokens))
            return Array(bufferPointer)
        }
    }
    
    deinit {
        if let sampling = sampling {
            llama_sampler_free(sampling)
        }
        llama_batch_free(batch)
        if let model = model {
            llama_model_free(model)
        }
        if let context = context {
            llama_free(context)
        }
        llama_backend_free()
    }
}
