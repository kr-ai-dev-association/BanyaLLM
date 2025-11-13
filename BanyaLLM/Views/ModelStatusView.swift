//
//  ModelStatusView.swift
//  BanyaLLM
//
//  Created by Tony-M4 on 11/13/25.
//

import SwiftUI

struct ModelStatusView: View {
    @ObservedObject var llamaManager: LlamaManager
    
    var body: some View {
        VStack(spacing: 12) {
            if llamaManager.isModelLoaded {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("모델 로드 완료")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(llamaManager.loadingProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // 시뮬레이션 모드 표시
            Text("⚠️ 시뮬레이션 모드 (llama.cpp 통합 필요)")
                .font(.caption2)
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
        }
        .padding(.vertical, 8)
    }
}

