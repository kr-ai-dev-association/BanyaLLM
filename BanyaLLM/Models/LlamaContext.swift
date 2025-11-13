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
    batch.token   [Int(batch.n_tokens)] = id
    batch.pos     [Int(batch.n_tokens)] = pos
    batch.n_seq_id[Int(batch.n_tokens)] = Int32(seq_ids.count)
    for i in 0..<seq_ids.count {
        batch.seq_id[Int(batch.n_tokens)]![Int(i)] = seq_ids[i]
    }
    batch.logits  [Int(batch.n_tokens)] = logits ? 1 : 0
    
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
    var n_len: Int32 = 512
    var n_cur: Int32 = 0
    var n_decode: Int32 = 0
    
    private let modelPath: String
    
    init(modelPath: String) {
        self.modelPath = modelPath
        self.batch = llama_batch_init(512, 0, 1)
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
        
        // 4. Temperature - 창의성 조절 (0.7 = 자연스러운 대화)
        llama_sampler_chain_add(self.sampling, llama_sampler_init_temp(0.7))
        
        // 5. Repeat Penalty - 반복 방지 (1.05 = 적당한 패널티)
        llama_sampler_chain_add(self.sampling, llama_sampler_init_penalties(
            512,    // last_n: 최근 512 토큰 고려
            1.05,   // repeat_penalty: 반복 패널티
            0.0,    // freq_penalty
            0.0     // presence_penalty
        ))
        
        // 6. Dist 샘플링 (최종 토큰 선택)
        llama_sampler_chain_add(self.sampling, llama_sampler_init_dist(UInt32.random(in: 0...1000)))
        
        print("🎛️ 샘플링 설정: Temp=0.7, Top-P=0.9, Min-P=0.05, Repeat=1.05")
        
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
        
        for i in 0..<tokens_list.count {
            llama_batch_add(&batch, tokens_list[i], Int32(i), [0], false)
        }
        batch.logits[Int(batch.n_tokens) - 1] = 1
        
        if llama_decode(context, batch) != 0 {
            print("❌ llama_decode() 실패")
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
            let new_token_str = String(cString: temporary_invalid_cchars + [0])
            temporary_invalid_cchars.removeAll()
            return new_token_str
        }
        
        let new_token_cchars = token_to_piece(token: new_token_id)
        temporary_invalid_cchars.append(contentsOf: new_token_cchars)
        let new_token_str: String
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
        
        llama_batch_clear(&batch)
        llama_batch_add(&batch, new_token_id, n_cur, [0], true)
        
        n_decode += 1
        n_cur += 1
        
        if llama_decode(context, batch) != 0 {
            print("❌ llama_decode 실패!")
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
