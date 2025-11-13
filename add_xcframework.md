# xcframework 추가 방법 (3분 소요)

## 🎯 목표
`llama.xcframework`를 Xcode 프로젝트에 추가하여 실제 LLM 추론을 활성화합니다.

## 📋 단계

### 1. Xcode에서 프로젝트 열기
```bash
open BanyaLLM.xcodeproj
```

### 2. xcframework 추가 (드래그 앤 드롭)

**방법 A: 파인더에서 드래그**
1. 파인더에서 프로젝트 폴더 열기
2. `llama.xcframework` 폴더를 찾기
3. Xcode의 프로젝트 네비게이터로 드래그
4. 다이얼로그에서:
   - ✅ "Copy items if needed" 체크 해제
   - ✅ "Create groups" 선택
   - ✅ "BanyaLLM" 타겟 선택
   - "Finish" 클릭

**방법 B: 메뉴에서 추가**
1. Xcode 프로젝트 네비게이터에서 `BanyaLLM` 프로젝트 클릭
2. `BanyaLLM` 타겟 선택
3. **General** 탭
4. "Frameworks, Libraries, and Embedded Content" 섹션
5. **+** 버튼 클릭
6. "Add Other..." → "Add Files..." 선택
7. `llama.xcframework` 선택
8. **"Embed & Sign"** 선택 (중요!)

### 3. 시스템 프레임워크 추가

같은 섹션에서 **+** 버튼 다시 클릭:
1. 검색창에 "Metal" 입력 → `Metal.framework` 선택 → Add
2. 검색창에 "Accelerate" 입력 → `Accelerate.framework` 선택 → Add

### 4. 브리징 헤더 설정 (선택 사항)

Build Settings에서:
1. 검색: "Objective-C Bridging Header"
2. 값 설정: `BanyaLLM/Models/LlamaBridge.h`

### 5. Build Settings 확인

1. **Framework Search Paths**에 `$(PROJECT_DIR)` 포함되어 있는지 확인
2. **Enable Bitcode**: No

## ✅ 확인 방법

빌드 시 다음 메시지가 나타나면 성공:
```
✅ 모델이 성공적으로 로드되었습니다
```

## ❌ 문제 해결

### "No such module 'llama'" 오류
→ xcframework가 "Embed & Sign"으로 설정되었는지 확인

### "Framework not found" 오류
→ Framework Search Paths에 `$(PROJECT_DIR)` 추가

### 빌드는 되지만 실행 시 크래시
→ Embed 설정이 "Do Not Embed"로 되어 있는지 확인 (Embed & Sign으로 변경)

## 🚀 다음 단계

1. Clean Build Folder (⌘⇧K)
2. Build (⌘B)
3. Run (⌘R)
4. 채팅창에서 메시지 입력
5. 실제 LLM 응답 확인!

