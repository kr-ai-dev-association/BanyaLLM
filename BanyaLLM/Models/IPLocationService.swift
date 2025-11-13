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
    private let baseURL = "https://ip-api.com/json"
    
    /// IP 주소를 기반으로 위치 정보 가져오기
    /// - Returns: 위치 정보 (도시, 국가, 위도, 경도), 실패 시 서울 강남구 기본값 반환
    func getLocationFromIP() async -> IPLocation {
        guard let url = URL(string: baseURL) else {
            // print("⚠️ IP 위치 URL 생성 실패: 기본값(서울 강남구) 반환")
            return getDefaultLocation()
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                // print("⚠️ IP 위치 응답 형식 오류: 기본값(서울 강남구) 반환")
                return getDefaultLocation()
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                // print("⚠️ IP 위치 HTTP 오류 (\(httpResponse.statusCode)): 기본값(서울 강남구) 반환")
                return getDefaultLocation()
            }
            
            let decoder = JSONDecoder()
            do {
                let locationResponse = try decoder.decode(IPLocationResponse.self, from: data)
                
                guard locationResponse.status == "success" else {
                    // print("⚠️ IP 위치 API 오류: 기본값(서울 강남구) 반환")
                    return getDefaultLocation()
                }
                
                return IPLocation(
                    city: locationResponse.city ?? "강남구",
                    country: locationResponse.country ?? "대한민국",
                    countryCode: locationResponse.countryCode ?? "KR",
                    latitude: locationResponse.lat ?? 37.5172,
                    longitude: locationResponse.lon ?? 127.0473,
                    region: locationResponse.regionName ?? "서울특별시",
                    timezone: locationResponse.timezone ?? "Asia/Seoul"
                )
            } catch {
                // print("❌ IP 위치 응답 디코딩 실패: \(error) - 기본값(서울 강남구) 반환")
                return getDefaultLocation()
            }
        } catch {
            // print("⚠️ IP 위치 정보 가져오기 실패: \(error.localizedDescription) - 기본값(서울 강남구) 반환")
            return getDefaultLocation()
        }
    }
    
    /// 기본 위치 정보 반환 (서울 강남구)
    private func getDefaultLocation() -> IPLocation {
        return IPLocation(
            city: "강남구",
            country: "대한민국",
            countryCode: "KR",
            latitude: 37.5172,
            longitude: 127.0473,
            region: "서울특별시",
            timezone: "Asia/Seoul"
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

