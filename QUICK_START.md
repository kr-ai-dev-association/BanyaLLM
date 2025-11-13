# 🚀 빠른 시작 가이드

Xcode가 열렸습니다! 이제 **2분 안에** xcframework를 추가할 수 있습니다.

## 📦 1단계: xcframework 추가 (30초)

### 방법 1: 드래그 앤 드롭 (가장 빠름)
1. 파인더에서 **llama.xcframework** 폴더 찾기
2. Xcode 왼쪽 프로젝트 네비게이터로 **드래그**
3. 체크박스 확인:
   - ⬜ Copy items (체크 해제)
   - ✅ BanyaLLM target (체크)
4. **Finish** 클릭

### 방법 2: General 탭에서 추가
1. 프로젝트 네비게이터에서 `BanyaLLM` (맨 위) 클릭
2. `BanyaLLM` 타겟 선택  
3. **General** 탭
4. "Frameworks, Libraries, and Embedded Content"에서 **+** 클릭
5. **Add Other...** → **Add Files...**
6. `llama.xcframework` 선택
7. **Embed & Sign** 선택 (중요!)

## ⚡ 2단계: 시스템 프레임워크 추가 (30초)

같은 위치("Frameworks, Libraries...")에서:
1. **+** 클릭 → "Metal" 검색 → **Metal.framework** 추가
2. **+** 클릭 → "Accelerate" 검색 → **Accelerate.framework** 추가

## 🔧 3단계: Build Settings 설정 (30초)

1. **Build Settings** 탭 (General 옆)
2. 검색: "Objective-C Bridging Header"
3. 값: `BanyaLLM/Models/LlamaBridge.h`

## ▶️ 4단계: 빌드 및 실행 (30초)

1. **⌘⇧K** (Clean Build Folder)
2. **⌘B** (Build)
3. **⌘R** (Run)

## ✅ 성공 확인

앱 실행 시 다음이 표시되면 성공:
- 상단에 "✅ 모델 로드 완료" 
- "⚠️ 시뮬레이션 모드" 메시지 **사라짐**
- 실제 LLM 응답 생성

## ❓ 문제 발생 시

### "No such module 'llama'"
→ xcframework가 "Embed & Sign"으로 설정되었는지 확인

### 빌드는 되지만 크래시
→ Metal.framework와 Accelerate.framework가 추가되었는지 확인

### 여전히 시뮬레이션 모드
→ LlamaContext.swift의 주석(`/* */`)을 제거해야 함

---

**소요 시간: 약 2-3분**  
**성공하면**: 4.6GB 모델로 실제 한국어 LLM 채팅!

