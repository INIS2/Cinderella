# Cinderella

프로젝트 신데렐라는 대여 후 반납된 Windows PC나 조치가 필요한 PC를 빠르게 정리해, 일반 사용자에게 다시 넘길 수 있는 상태로 되돌리는 운영 보조 도구입니다.

포맷은 확실하지만 오래 걸리고 세팅과 인증을 다시 해야 합니다. 이미지는 안정적이지만 업데이트 주기에 맞춰 새로 만들어야 합니다. 수동 정리는 빠르지만 누락이 생길 수 있습니다. Cinderella는 이 사이에서, 자주 바뀌는 표면 영역을 먼저 점검하고 정리하는 방향을 잡습니다.

## 개발 방향

구조는 `Scan -> Plan -> Action` 3단계로 나눕니다.

- `Scan`: 현재 PC 상태를 읽고 정리 대상과 변경 가능성이 있는 항목을 수집합니다.
- `Plan`: 실제 조치 전에 어떤 작업을 할지 사람이 확인할 수 있는 계획을 만듭니다.
- `Action`: 확인된 계획만 실행합니다. 삭제나 정리 작업은 명시적인 실행 옵션을 요구합니다.

초기 MVP는 다음 항목에 집중합니다.

- Windows Update 적용 가능 업데이트 확인 및 업데이트 설정 화면 열기
- Chrome/Edge 브라우저 캐시, 기록 등 사용자 흔적 정리
- 다운로드, D 드라이브 등 지정 경로의 파일 정리
- 휴지통 비우기

이후 확장 항목은 구조 안에 자리만 만들어 둡니다.

- 바탕화면 아이콘 및 바로가기 세팅
- 레지스트리/환경설정 점검
- 설치 프로그램 기준 목록 비교
- 상세 리포트 생성
- 기준 이미지 또는 정기 점검 프로세스 연동

## 현재 구조

```text
.
├── config
│   └── cinderella.config.json
├── src
│   ├── Cinderella.Core.ps1
│   ├── Cinderella.Gui.ps1
│   └── Cinderella.ps1
├── Cinderella.cmd
├── LICENSE
└── README.md
```

## 실행 예시

GUI 실행:

```powershell
.\Cinderella.cmd
```

또는 PowerShell에서 직접 실행할 수 있습니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\src\Cinderella.Gui.ps1
```

GUI에서는 `Scan`, `Plan`, `Run Selected` 순서로 진행합니다.

- `Scan`: 전체 점검 항목과 추후 구현 슬롯까지 보여줍니다. 화면 표기는 한/영 병기입니다.
- `Candidates` / `실행 후보`: 실제 실행 가능한 항목만 체크박스로 보여줍니다. 실행 중인 브라우저나 안전상 차단된 경로는 제외됩니다.
- `Run Selected` / `선택 실행`: 체크된 항목만 실행합니다. 실행 전 확인 창이 한 번 더 뜨고, 실행 결과는 JSON 리포트로 저장됩니다.

Scan과 Action은 백그라운드 Job으로 실행합니다. Windows Update 확인처럼 시간이 걸리는 작업 중에도 창 이동과 언어 전환이 가능하며, 진행 중에는 상태 문구와 진행 바가 표시됩니다.

GUI 우측 상단의 언어 선택에서 한국어/English 표시를 바꿀 수 있습니다. 언어를 바꿔도 현재 Scan 결과, 실행 후보 목록, 체크 상태는 초기화하지 않습니다.

CLI와 GUI는 같은 `src/Cinderella.Core.ps1` 로직을 사용합니다. GUI는 일반 사용자를 위한 기본 진입점이고, CLI는 개발 및 점검용으로 남겨둡니다.

CLI 기본 실행은 `Plan`입니다. 현재 PC를 스캔한 뒤 실행 계획만 출력합니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\src\Cinderella.ps1
```

스캔 결과만 확인합니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\src\Cinderella.ps1 -Stage Scan
```

실제 조치를 실행하려면 `Action`과 `-ConfirmAction`을 같이 넘겨야 합니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\src\Cinderella.ps1 -Stage Action -ConfirmAction
```

## 안전 원칙

- 삭제/정리 작업은 기본 실행되지 않습니다.
- 정리 대상 경로는 `config/cinderella.config.json`에 명시된 항목만 사용합니다.
- 시스템 경로, 프로그램 설치 경로, 사용자 홈 전체 같은 넓은 경로는 MVP 대상에서 제외합니다.
- `Documents` 전체 정리는 기본 대상에서 제외했습니다.
- `D:\`는 설정에서 명시적으로 `allowRoot: true`를 둔 경우에만 대상으로 잡습니다.
- 파일 정리는 기본적으로 삭제가 아니라 `%SYSTEMDRIVE%\Cinderella_Quarantine` 아래로 격리 이동합니다.
- Chrome/Edge가 실행 중이면 해당 브라우저 정리는 `Blocked/Skip` 처리합니다.
- Scan/Plan에는 정리 대상의 파일 수와 용량이 표시됩니다.
- Windows Update는 로컬 Windows Update Agent로 적용 가능한 업데이트를 검색해 `Latest`, `Needs Action`, `Check Failed` 상태로 표시합니다.
- Action 결과는 `reports/` 아래 JSON 파일로 저장됩니다.
- Action 단계는 관리자 권한 필요 여부와 실제 조치 가능 여부를 점검하면서 확장합니다.
