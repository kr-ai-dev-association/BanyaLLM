//
//  ModelStatusView.swift
//  BanyaLLM
//
//  Created by Tony-M4 on 11/13/25.
//

import SwiftUI

struct ModelStatusView: View {
    @ObservedObject var llamaManager: LlamaManager
    @State private var showCompletionMessage: Bool = false
    
    var body: some View {
        VStack(spacing: 12) {
            if llamaManager.isModelLoaded {
                if showCompletionMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("모델 로드 완료")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                }
            } else {
                HStack {
                    ProgressView(value: llamaManager.loadingProgressValue)
                        .scaleEffect(0.7)
                    Text(llamaManager.loadingProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // 시뮬레이터/실제 기기 구분 표시
            #if targetEnvironment(simulator)
            Text("📱 시뮬레이터 모드 (실제 기기에서 LLM 사용 가능)")
                .font(.caption2)
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            #else
            if llamaManager.isModelLoaded {
                Text("⚡ MPS 가속 모드")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
            }
            #endif
        }
        .padding(.vertical, 8)
        .onChange(of: llamaManager.loadingProgressValue) { oldValue, newValue in
            // 프로그래스바가 100%가 되면 완료 메시지 표시
            if newValue >= 1.0 && !showCompletionMessage {
                withAnimation {
                    showCompletionMessage = true
                }
                // 2초 후 메시지 사라지게
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2초
                    withAnimation {
                        showCompletionMessage = false
                    }
                }
            }
        }
    }
}

