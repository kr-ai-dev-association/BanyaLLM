//
//  TavilyService.swift
//  BanyaLLM
//
//  Created by Tony-M4 on 11/13/25.
//

import Foundation

/// Tavily Web Search API 서비스
class TavilyService {
    private let apiKey: String
    private let baseURL = "https://api.tavily.com/search"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    /// 웹 검색 수행
    /// - Parameter query: 검색 쿼리
    /// - Returns: 검색 결과 (제목, URL, 내용)
    func search(query: String) async throws -> [SearchResult] {
        guard let url = URL(string: baseURL) else {
            throw TavilyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "api_key": "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",
            "query": query,
            "search_depth": "basic",
            "max_results": 5
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TavilyError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw TavilyError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        let searchResponse = try decoder.decode(TavilySearchResponse.self, from: data)
        
        return searchResponse.results
    }
}

// MARK: - Models

struct TavilySearchResponse: Codable {
    let results: [SearchResult]
}

struct SearchResult: Codable {
    let title: String
    let url: String
    let content: String
}

enum TavilyError: Error {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError
}

