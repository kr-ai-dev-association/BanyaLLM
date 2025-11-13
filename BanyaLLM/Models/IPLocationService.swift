//
//  IPLocationService.swift
//  BanyaLLM
//
//  Created by Tony-M4 on 11/13/25.
//

import Foundation
import CoreLocation

/// IP 기반 위치 서비스
class IPLocationService {
    private let baseURL = "http://ip-api.com/json"
    
    /// IP 주소를 기반으로 위치 정보 가져오기
    /// - Returns: 위치 정보 (도시, 국가, 위도, 경도)
    func getLocationFromIP() async throws -> IPLocation? {
        guard let url = URL(string: baseURL) else {
            throw IPLocationError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IPLocationError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw IPLocationError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        let locationResponse = try decoder.decode(IPLocationResponse.self, from: data)
        
        guard locationResponse.status == "success" else {
            throw IPLocationError.apiError(message: locationResponse.message ?? "Unknown error")
        }
        
        return IPLocation(
            city: locationResponse.city ?? "",
            country: locationResponse.country ?? "",
            countryCode: locationResponse.countryCode ?? "",
            latitude: locationResponse.lat ?? 0.0,
            longitude: locationResponse.lon ?? 0.0,
            region: locationResponse.regionName ?? "",
            timezone: locationResponse.timezone ?? ""
        )
    }
}

// MARK: - Models

struct IPLocationResponse: Codable {
    let status: String
    let message: String?
    let country: String?
    let countryCode: String?
    let region: String?
    let regionName: String?
    let city: String?
    let zip: String?
    let lat: Double?
    let lon: Double?
    let timezone: String?
    let isp: String?
    let org: String?
    let `as`: String?
    let query: String?
}

struct IPLocation {
    let city: String
    let country: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
    let region: String
    let timezone: String
    
    var displayName: String {
        if !city.isEmpty && !country.isEmpty {
            return "\(city), \(country)"
        } else if !country.isEmpty {
            return country
        } else {
            return "위치 정보 없음"
        }
    }
}

enum IPLocationError: Error {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case apiError(message: String)
    case decodingError
}

