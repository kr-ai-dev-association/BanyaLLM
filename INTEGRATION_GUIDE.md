# llama.cpp 통합 가이드

`llama.xcframework`가 생성되었습니다! 이제 Xcode에서 수동으로 추가해야 합니다.

## 단계 1: Xcode에서 xcframework 추가

1. Xcode에서 `BanyaLLM.xcodeproj` 열기
2. 프로젝트 네비게이터에서 `BanyaLLM` 프로젝트 선택
3. `BanyaLLM` 타겟 선택
4. **General** 탭으로 이동
5. "Frameworks, Libraries, and Embedded Content" 섹션에서 **+** 버튼 클릭
6. "Add Other..." → "Add Files..." 선택
7. 프로젝트 루트의 `llama.xcframework` 선택
8. "Embed & Sign" 선택

## 단계 2: 필요한 시스템 프레임워크 추가

같은 섹션에서 **+** 버튼을 다시 클릭하고:
- `Metal.framework` 추가
- `Accelerate.framework` 추가

## 단계 3: 코드 활성화

`BanyaLLM/Models/LlamaContext.swift` 파일을 열고:

1. 파일 상단에 import 추가:
```swift
import llama
```

2. `initialize()` 함수의 주석 처리된 코드 활성화 (/*   */ 제거)
3. `completionLoop()` 함수의 주석 처리된 코드 활성화
4. `deinit`의 주석 처리된 코드 활성화

## 단계 4: 빌드 및 테스트

1. `Product` → `Clean Build Folder` (⌘⇧K)
2. iPhone Simulator 선택
3. `Product` → `Run` (⌘R)

## 예상 결과

- 앱 실행 시 "✅ 모델이 성공적으로 로드되었습니다" 로그 확인
- 실제 LLM 모델로 한국어 응답 생성
- MPS 가속으로 빠른 추론 속도

## 문제 해결

### "No such module 'llama'" 오류
- xcframework가 제대로 추가되었는지 확인
- Build Settings에서 Framework Search Paths 확인

### 메모리 부족 오류
- 시뮬레이터가 아닌 실제 기기에서 테스트
- 백그라운드 앱 종료

### 느린 응답 속도
- 실제 기기에서 테스트 (시뮬레이터는 GPU 가속 없음)
- `n_gpu_layers` 값 조정

## 다음 단계

1. 온디바이스에서 테스트
2. 응답 품질 평가
3. 성능 최적화 (배치 크기, 컨텍스트 길이 등)
4. 대화 기록 저장 기능 추가

