//
//  ModelPickerView.swift
//  BanyaLLM
//
//  모델 파일 선택 UI
//

import SwiftUI
import UniformTypeIdentifiers

struct ModelPickerView: View {
    @ObservedObject var llamaManager: LlamaManager
    @State private var showFilePicker = false
    @State private var selectedFileURL: URL?
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.circle")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.blue)
            
            Text("모델 파일 선택")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("GGUF 형식의 LLM 모델을 선택하세요")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let selectedURL = selectedFileURL {
                VStack(spacing: 8) {
                    Text("선택된 파일:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(selectedURL.lastPathComponent)
                        .font(.footnote)
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    
                    if let fileSize = getFileSize(url: selectedURL) {
                        Text("크기: \(fileSize)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Button(action: {
                showFilePicker = true
            }) {
                HStack {
                    Image(systemName: "folder.circle.fill")
                    Text(selectedFileURL == nil ? "모델 파일 선택" : "다른 파일 선택")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 15)
                .background(Color.blue)
                .cornerRadius(25)
            }
            
            if selectedFileURL != nil {
                Button(action: {
                    loadSelectedModel()
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("이 모델 사용")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 15)
                    .background(Color.green)
                    .cornerRadius(25)
                }
            }
            
            Divider()
                .padding(.vertical)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("💡 모델 위치:")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text("/Volumes/Transcend/Projects/BanyaLLM/BanyaLLM/llama31-banyaa-q4_k_m.gguf")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
        }
        .padding()
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedFileURL = url
                    print("✅ 파일 선택됨: \(url.path)")
                }
            case .failure(let error):
                print("❌ 파일 선택 실패: \(error)")
            }
        }
    }
    
    private func getFileSize(url: URL) -> String? {
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            return nil
        }
        
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    private func loadSelectedModel() {
        guard let url = selectedFileURL else { return }
        
        // 보안 범위 리소스 접근 시작
        guard url.startAccessingSecurityScopedResource() else {
            print("❌ 파일 접근 권한 없음")
            return
        }
        
        // 모델 경로 저장 및 로드
        UserDefaults.standard.set(url.path, forKey: "selectedModelPath")
        UserDefaults.standard.set(url.bookmarkData(), forKey: "selectedModelBookmark")
        
        print("✅ 모델 경로 저장: \(url.path)")
        
        // 모델 로드
        Task {
            await llamaManager.loadModelFromPath(url.path)
        }
    }
}

extension URL {
    func bookmarkData() -> Data? {
        try? self.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}

