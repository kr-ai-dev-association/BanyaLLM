#!/bin/bash
cd "$(dirname "$0")"
open BanyaLLM.xcodeproj
echo "✅ Xcode가 열렸습니다!"
echo ""
echo "📋 다음 단계:"
echo "1. add_xcframework.md 파일을 열어서 따라하세요"
echo "2. llama.xcframework를 프로젝트에 드래그하세요"
echo "3. Metal.framework와 Accelerate.framework를 추가하세요"
echo "4. Build & Run!"
