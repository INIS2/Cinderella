# Cinderella 2.0 MVP

공용·대여 Windows PC를 다음 사용자에게 넘기기 전에, 표면에 남은 사용자 흔적을 빠르게 정리하는 작은 portable 도구입니다. 설치 프로그램이나 별도 런타임 없이 `Cinderella.cmd`를 실행합니다.

## 개발자 코멘트

12시가 되면 마법으로 만든 드레스가 사라지고 집에 가야 하는 신데렐라처럼, 이 프로젝트는 대여 후 반납된 Windows PC를 한순간에 다시 사용할 수 있는 상태로 돌려놓는 것을 목표로 합니다.

초기화에는 여러 방법이 있고 각각 장단점이 있습니다.

- **포맷**: 확실하지만 프로그램 재설치와 인증이 필요합니다.
- **이미지 복원**: 기준 상태를 유지할 수 있지만 이미지 관리와 시간이 필요합니다.
- **수동 정리**: 빠르지만 사람이 놓치는 부분이 생길 수 있습니다.

Cinderella는 이 사이에서, 일반 사용자가 조작할 수 있는 표면 영역을 먼저 점검하고 정리합니다. 이후에는 변경 감지와 기준 이미지·정기 점검 연동으로 확장할 수 있습니다.

초기 기획에서 다루는 영역은 다음과 같습니다.

- Chrome·Edge 브라우저의 기록, 로그, 캐시 등 사용자 흔적
- 다운로드·문서·사진·동영상 등 주요 사용자 경로의 파일
- 추가 디스크의 사용자 파일
- 휴지통
- 향후 확장: 설치 프로그램 대조, 환경 설정 점검, 배경화면·바로가기 정리, 상세 리포트

## 현재 구현 범위

- Chrome·Edge에서 감지된 프로필별 공식 `clearBrowserData` 화면 열기
- 브라우저 삭제 버튼은 사용자가 직접 누르도록 유지
- 기본 파일 대상: `Downloads`, `Documents`, `Pictures`, `Videos`
- 파일은 폴더 자체가 아니라 해당 폴더의 하위 내용만 정리
- C 드라이브 외 추가 고정 디스크는 Advanced 또는 `--drive`로 선택한 경우에만 정리
- 휴지통 비우기
- CLI와 최소 GUI가 같은 `Cinderella.ps1`을 사용
- 미리 보기(`scan`, `--dry-run`), 명시적 실행 확인(`--yes`), 보호 경로 차단

브라우저의 북마크, 저장된 비밀번호, 자동 완성, 확장 프로그램, 프로필 자체는 이 MVP가 직접 삭제하지 않습니다. 브라우저가 실행 중이면 모든 프로필 정리창을 안정적으로 열 수 없으므로 먼저 브라우저를 닫아야 합니다.

## 파일 구조

```text
.
├── Cinderella.cmd       # Windows용 portable 실행 래퍼
├── Cinderella.ps1       # CLI·GUI·정리 로직이 들어 있는 단일 스크립트
├── README.md            # 사용·개발 안내
├── LICENSE
└── .gitignore
```

별도 설치 폴더나 설정 파일이 필요하지 않습니다. `Cinderella.cmd`와 `Cinderella.ps1`을 같은 폴더에 둔 채 USB나 네트워크 폴더에서 실행할 수 있습니다.

## 실행 방법

### 1. 대화형 시작

```powershell
.\Cinderella.cmd
```

화면에서 다음 순서로 진행합니다.

```text
실행
 → CLI / GUI 선택
 → KR / EN 선택
 → 대상 확인(Check / Go)
 → 기본 시행(Default execution) 또는 옵션 시행(Option execution)
 → 브라우저 정리(Default / Advanced)
 → 파일 정리(Default / Advanced)
 → 휴지통(Default)
 → 변경 대상 확인(Go Clean)
 → 결과(Result)
 → 종료(End & Close)
```

`Default execution`을 선택하면 브라우저는 모든 감지 프로필(Standard), 파일은 기본 네 경로, 휴지통은 기본값으로 진행하고 세부 옵션을 건너뜁니다. `Option execution`에서는 브라우저 프로필과 추가 디스크를 체크할 수 있습니다.

### 2. GUI 직접 실행

```powershell
.\Cinderella.cmd gui
```

또는 다음처럼 PowerShell에서 직접 실행합니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Cinderella.ps1 gui
```

### 3. CLI 미리 보기와 실행

```powershell
# 대상과 예상 용량만 확인. 아무것도 삭제하지 않음
.\Cinderella.cmd scan
.\Cinderella.cmd clean --dry-run

# 기본 범위 실행
.\Cinderella.cmd clean --yes

# 자동화 Standard 실행
# 모든 감지 브라우저 프로필 정리창 + 기본 네 경로 + 휴지통
.\Cinderella.cmd clean --all --yes

# 추가 디스크를 명시적으로 포함
.\Cinderella.cmd clean --files --drive D: --yes

# 특정 폴더를 파일 정리 대상으로 추가
.\Cinderella.cmd clean --files --path D:\Temp\ReturnedPC --yes
```

`--all --yes`도 브라우저의 삭제 버튼을 자동으로 누르지는 않습니다. Chrome·Edge 창이 열린 뒤 각 창에서 기간을 `전체 기간(All time)`으로 선택하고 삭제 버튼을 직접 눌러야 합니다.

PowerShell 스크립트의 짧은 옵션을 직접 사용할 수도 있습니다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Cinderella.ps1 clean -All -Yes
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Cinderella.ps1 clean -Files -Drive D: -DryRun
```

## 동작 단계: Scan → Plan → Action

- **Scan**: 설치된 브라우저, 사용자 프로필, 기본 경로, 추가 디스크를 읽습니다.
- **Plan**: 실행 전에 정리 대상과 예상 용량을 목록으로 보여줍니다.
- **Action**: 확인된 계획만 실행합니다. 파일·휴지통 작업은 `--yes` 또는 GUI의 `Go Clean` 확인이 필요합니다.

브라우저는 Action 단계에서 프로필별 공식 정리 페이지를 열고, 파일 정리는 지정 폴더의 하위 항목을 삭제하며, 휴지통은 Windows `Clear-RecycleBin` 명령으로 비웁니다. 시스템 드라이브 루트나 보호된 경로 자체는 대상으로 삼지 않습니다.

## 안전 원칙

- 먼저 `scan` 또는 `clean --dry-run`으로 대상을 확인합니다.
- 기본 대상은 네 개의 사용자 폴더이며, 추가 디스크는 명시적으로 선택해야 합니다.
- 폴더 자체는 삭제하지 않고 내부 항목만 정리합니다.
- C 드라이브 루트, 시스템 경로, 프로그램 설치 경로는 보호합니다.
- 실행 중인 Chrome·Edge는 자동 종료하지 않습니다.
- 브라우저의 북마크·비밀번호·자동 완성·확장 프로그램·프로필 자체는 건드리지 않습니다.
- 정리 후 결과는 화면에 표시되며, 이 MVP는 별도 보고서 파일을 만들지 않습니다.

## 개발 방향

현재는 단일 PowerShell 파일로 작게 유지합니다. 기능이 커지면 아래 순서로 분리할 수 있습니다.

1. 설치 프로그램 기준 목록 비교
2. 레지스트리·환경 설정 변경 감지
3. 바탕화면 배경과 바로가기 기준화
4. JSON/CSV 상세 리포트
5. 기준 이미지 및 정기 점검 프로세스 연동

기능을 추가할 때도 `Scan → Plan → Action` 경계를 유지하고, 사용자가 확인할 수 있는 계획을 먼저 만든 뒤 실제 변경을 실행하는 것을 원칙으로 합니다.
