# Cinderella 2.0 MVP

공용·대여 Windows PC에서 남은 일반 사용자 데이터를 빠르게 정리하는 작은 portable 도구입니다. 설치나 별도 런타임 없이 `Cinderella.cmd`를 실행합니다.

## 이번 구현 범위

- Chrome·Edge의 모든 감지된 프로필에 공식 `clearBrowserData` 화면을 열기
- 사용자가 브라우저에서 전체 기간과 삭제 항목을 확인한 뒤 직접 삭제
- Downloads, Documents, Pictures, Videos의 **내용만** 기본 정리
- C 드라이브 외 추가 디스크를 Advanced 목록으로 보여주고 선택한 디스크의 하위 내용만 정리
- 휴지통 비우기
- 대화형 CLI, 자동화 CLI, 최소 GUI가 하나의 PowerShell 파일을 공유
- 미리 보기와 명시적 확인, 브라우저 실행 감지, 보호 경로 및 드라이브 루트 차단

브라우저의 삭제 버튼은 Cinderella가 자동으로 누르지 않습니다. 북마크, 저장된 비밀번호, 자동 완성 데이터, 확장 프로그램, 프로필 자체 삭제는 별도 기능으로 남겨둡니다. 추가 디스크는 기본 선택되지 않으며 Advanced 체크 또는 `--drive`로 명시한 경우에만 정리합니다.

## 사용

대화형 실행은 다음 순서로 진행됩니다.

```text
실행
 → CLI / GUI 선택
 → KR / EN 선택
 → 대상 확인(Check / Go)
 → 기본 시행 또는 옵션 시행
 → 브라우저 정리(Default / Advanced)
 → 파일 정리(Default / Advanced)
 → 휴지통(Default)
 → 변경 대상 확인(Go Clean)
 → 결과(Result)
 → 종료(End & Close)
```

`기본 시행(Default execution)`을 고르면 뒤의 세부 옵션 화면을 건너뛰고 바로 `Go Clean`으로 이동합니다. `옵션 시행(Option execution)`에서는 브라우저 프로필과 추가 디스크를 선택할 수 있습니다.

```powershell
# 대화형 CLI
.\Cinderella.cmd

# 아무것도 지우지 않는 미리 보기 (GNU 스타일 긴 옵션도 지원)
.\Cinderella.cmd scan
.\Cinderella.cmd clean --dry-run

# 기본 범위 정리 (브라우저별 모든 프로필의 삭제 화면 열기)
.\Cinderella.cmd clean --yes

# 자동화 모드: Standard 브라우저 흐름 + 기본 파일 정리 + 휴지통
.\Cinderella.cmd clean --all --yes

# 추가 디스크를 CLI에서 명시적으로 선택 (예: D:)
.\Cinderella.cmd clean --files --drive D: --yes

# 작은 GUI
.\Cinderella.cmd gui
```

## 다음 단계

1. 실제 대여 PC에서 `scan`으로 감지 프로필·기본 경로·추가 디스크를 검증한다.
2. Chrome/Edge를 모두 닫은 상태에서 `clean --all --yes`를 실행하고, 각 창에서 전체 기간을 선택한다.
3. GUI Advanced에서 추가 디스크를 선택하면 해당 디스크의 하위 내용까지 정리한다.

배포 파일은 현재 `Cinderella.ps1`과 실행용 `Cinderella.cmd` 두 개입니다. README는 개발·운영 안내용이며 배포 시 제외해도 됩니다.
