# BanyaLLM - iOS 로컬 LLM 채팅 앱

Swift로 구현된 iOS용 로컬 LLM 채팅 애플리케이션입니다. MPS(Metal Performance Shaders) 가속을 활용하여 디바이스에서 직접 LLM을 실행합니다.

## 기능

- ✅ 스플래시 화면
- ✅ 메신저 스타일의 채팅 UI
- ✅ 스트리밍 응답 지원
- ✅ LLM 통합 구조 (시뮬레이션 모드)
- 🚧 llama.cpp 통합 (진행 중)
- 🚧 MPS 가속 (진행 중)

## 프로젝트 구조

```
BanyaLLM/
├── Models/
│   ├── ChatMessage.swift          # 채팅 메시지 모델
│   ├── LlamaContext.swift         # llama.cpp 래퍼
│   └── LlamaManager.swift         # LLM 관리자
├── ViewModels/
│   └── ChatViewModel.swift        # 채팅 로직
├── Views/
│   ├── SplashView.swift          # 스플래시 화면
│   └── ChatView.swift            # 채팅 UI
└── llama.cpp/
    └── LibLlama.swift            # llama.cpp Swift 바인딩
```

## 현재 상태

앱의 UI/UX와 기본 구조는 완성되었으며, **시뮬레이션 모드**로 동작합니다. 실제 LLM 추론을 위해서는 llama.cpp를 통합해야 합니다.

## llama.cpp 통합 방법

### 1단계: llama.cpp xcframework 빌드

```bash
# llama.cpp 클론
git clone https://github.com/ggerganov/llama.cpp.git
cd llama.cpp

# iOS용 xcframework 빌드
./build-xcframework.sh

# 빌드 결과는 build-apple/llama.xcframework에 생성됩니다
```

### 2단계: Xcode 프로젝트에 추가

1. `llama.xcframework`를 프로젝트 루트에 복사
2. Xcode에서 프로젝트 선택
3. `BanyaLLM` 타겟 선택
4. "General" 탭에서 "Frameworks, Libraries, and Embedded Content"에 `llama.xcframework` 추가
5. "Embed & Sign" 선택

### 3단계: 필요한 프레임워크 추가

- `Metal.framework`
- `Accelerate.framework`

### 4단계: 코드 활성화

`BanyaLLM/Models/LlamaContext.swift` 파일에서 주석 처리된 llama.cpp 코드를 활성화합니다:

```swift
// TODO 주석을 제거하고 실제 llama.cpp API 호출 코드 활성화
```

### 5단계: 모델 파일 준비

`llama31-banyaa-q4_k_m.gguf` 파일을 다음 위치에 배치:
- 개발 중: `/Volumes/Transcend/Projects/BanyaLLM/BanyaLLM/`
- 배포: 앱 번들 또는 Documents 디렉토리

## MPS 가속 설정

llama.cpp는 자동으로 MPS(Metal Performance Shaders)를 감지하고 사용합니다. 시뮬레이터에서는 CPU만 사용하고, 실제 디바이스에서는 GPU 가속이 활성화됩니다.

```swift
#if targetEnvironment(simulator)
model_params.n_gpu_layers = 0  // 시뮬레이터: CPU만
#else
model_params.n_gpu_layers = 999  // 실제 기기: GPU 최대 활용
#endif
```

## 빌드 및 실행

```bash
# Xcode에서 실행
open BanyaLLM.xcodeproj

# 또는 커맨드 라인
xcodebuild -project BanyaLLM.xcodeproj \
  -scheme BanyaLLM \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

## 시스템 요구사항

- Xcode 15.0 이상
- iOS 18.5 이상
- Swift 5.0 이상
- 최소 6GB RAM (모델 크기에 따라 다름)

## 모델 정보

- 모델: Llama 3.1 (Banya 튜닝)
- 양자화: Q4_K_M
- 크기: 4.6GB
- 형식: GGUF

## 문제 해결

### 빌드 실패

1. **DerivedData 정리**:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/*
   ```

2. **디스크 공간 확인**: 모델 파일이 크므로 충분한 공간 필요

3. **코드 서명 오류**: 개발자 계정 설정 확인

### 런타임 오류

1. **모델을 찾을 수 없음**: `LlamaManager.swift`에서 경로 확인
2. **메모리 부족**: 백그라운드 앱 종료 후 재시도
3. **MPS 오류**: 시뮬레이터가 아닌 실제 기기에서 테스트

## 라이선스

이 프로젝트는 llama.cpp를 사용하며 MIT 라이선스를 따릅니다.

## 참고 자료

- [llama.cpp](https://github.com/ggerganov/llama.cpp)
- [llama.cpp iOS 예제](https://github.com/ggerganov/llama.cpp/tree/master/examples/llama.swiftui)
- [Metal Performance Shaders](https://developer.apple.com/documentation/metalperformanceshaders)

## 개발 로드맵

- [x] 기본 UI/UX 구현
- [x] 채팅 인터페이스
- [x] LLM 통합 구조
- [ ] llama.cpp xcframework 통합
- [ ] 실제 모델 추론
- [ ] 성능 최적화
- [ ] 대화 기록 저장
- [ ] 다양한 모델 지원

