[CmdletBinding()]
param(
  [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $PSScriptRoot "Cinderella.Core.ps1")

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  $ConfigPath = Join-Path $PSScriptRoot "..\config\cinderella.config.json"
}

$script:config = Read-CinderellaConfig $ConfigPath
$script:scanItems = @()
$script:planItems = @()
$script:currentItems = @()
$script:currentSelectable = $false
$script:language = "ko"
$script:statusKey = "ready"
$script:activeJob = $null
$script:activeOperation = ""

function Convert-CinderellaDisplayText {
  param([string]$Value)

  $ko = @{
    "Privilege" = "권한";
    "WindowsUpdate" = "윈도우 업데이트";
    "BrowserCleanup" = "브라우저 정리";
    "FileCleanup" = "파일 정리";
    "RecycleBin" = "휴지통";
    "Future" = "추후 구현";
    "Report" = "리포트";
    "Admin" = "관리자";
    "Standard" = "일반 권한";
    "Latest" = "최신";
    "NeedsAction" = "조치 필요";
    "CheckFailed" = "확인 실패";
    "Found" = "발견";
    "Missing" = "없음";
    "Ready" = "준비됨";
    "Blocked" = "차단됨";
    "Available" = "가능";
    "Reserved" = "예약됨";
    "Done" = "완료";
    "Failed" = "실패";
    "Partial" = "일부 완료";
    "Skipped" = "건너뜀";
    "Started" = "시작됨";
    "Saved" = "저장됨";
    "Skip" = "건너뜀";
    "Clean target" = "대상 정리";
    "Clean children" = "하위 항목 정리";
    "Empty recycle bin" = "휴지통 비우기";
    "Open Windows Update settings" = "업데이트 설정 열기";
    "Not implemented" = "미구현";
  }

  if ($script:language -eq "ko" -and $ko.ContainsKey($Value)) {
    return $ko[$Value]
  }

  return $Value
}

function Get-CinderellaText {
  param([string]$Key)

  $ko = @{
    title = "Cinderella";
    description = "반납 Windows PC 정리 흐름";
    scan = "검사";
    plan = "실행 후보";
    action = "선택 실행";
    close = "닫기";
    ready = "준비됨. 검사를 누르세요.";
    scanning = "검사 중입니다. Windows Update 확인은 시간이 걸릴 수 있습니다...";
    scanDone = "검사 완료. 발견 항목과 예약 항목을 확인하세요.";
    planning = "실행 후보를 모으는 중입니다...";
    planReady = "실행 후보 준비됨. 실행하지 않을 항목은 체크 해제하세요.";
    actionRunning = "선택한 항목을 실행 중입니다...";
    actionDone = "실행 완료. 결과 행을 확인하세요.";
    noSelection = "선택된 작업이 없습니다.";
    noSelectionTitle = "신데렐라";
    confirmTitle = "실행 확인";
    scanFailed = "검사 실패";
    planFailed = "실행 후보 생성 실패";
    actionFailed = "실행 실패";
    confirmTemplate = "선택한 작업 {0}개를 실행할까요? 파일이 삭제되거나 격리 이동될 수 있습니다.";
  }
  $en = @{
    title = "Cinderella";
    description = "Scan -> Candidates -> Action flow for returned Windows PCs.";
    scan = "Scan";
    plan = "Candidates";
    action = "Run Selected";
    close = "Close";
    ready = "Ready. Click Scan.";
    scanning = "Scanning. Windows Update check can take a while...";
    scanDone = "Scan complete. Review detected and reserved items.";
    planning = "Collecting runnable candidates...";
    planReady = "Candidates ready. Uncheck anything you do not want to run.";
    actionRunning = "Running selected actions...";
    actionDone = "Action complete. Review the result rows.";
    noSelection = "No selected actions.";
    noSelectionTitle = "Cinderella";
    confirmTitle = "Confirm Action";
    scanFailed = "Scan failed";
    planFailed = "Candidate collection failed";
    actionFailed = "Action failed";
    confirmTemplate = "Run {0} selected action(s)? This may remove or quarantine files.";
  }

  if ($script:language -eq "ko") {
    return $ko[$Key]
  }

  return $en[$Key]
}

function Get-CinderellaColumnHeaders {
  if ($script:language -eq "ko") {
    return @{
      module = "모듈";
      name = "이름";
      status = "상태";
      action = "조치";
      itemCount = "항목 수";
      sizeBytes = "바이트";
      path = "경로";
      note = "메모";
    }
  }

  return @{
    module = "Module";
    name = "Name";
    status = "Status";
    action = "Action";
    itemCount = "Items";
    sizeBytes = "Bytes";
    path = "Path";
    note = "Note";
  }
}

function Set-CinderellaGrid {
  param(
    $Grid,
    $Items,
    [bool]$Selectable,
    [int[]]$SelectedIndexes = @()
  )

  $script:currentItems = @($Items)
  $script:currentSelectable = $Selectable
  $Grid.Rows.Clear()
  for ($index = 0; $index -lt $Items.Count; $index++) {
    $item = $Items[$index]
    $rowIndex = $Grid.Rows.Add()
    $row = $Grid.Rows[$rowIndex]
    $row.Cells["selected"].Value = $Selectable -and (($SelectedIndexes.Count -eq 0) -or ($SelectedIndexes -contains $index))
    $row.Cells["module"].Value = Convert-CinderellaDisplayText $item.module
    $row.Cells["name"].Value = $item.name
    $row.Cells["status"].Value = Convert-CinderellaDisplayText $item.status
    $row.Cells["action"].Value = Convert-CinderellaDisplayText $item.action
    $row.Cells["itemCount"].Value = $item.itemCount
    $row.Cells["sizeBytes"].Value = $item.sizeBytes
    $row.Cells["path"].Value = $item.path
    $row.Cells["note"].Value = $item.note
    $row.Cells["itemIndex"].Value = $index
    $row.Cells["selected"].ReadOnly = -not $Selectable
  }
}

function Get-CheckedIndexes {
  param($Grid)

  $Grid.EndEdit()
  $indexes = @()
  foreach ($row in $Grid.Rows) {
    if ($row.IsNewRow) {
      continue
    }

    if ([bool]$row.Cells["selected"].Value) {
      $indexes += [int]$row.Cells["itemIndex"].Value
    }
  }

  return $indexes
}

function Set-CinderellaBusy {
  param(
    [bool]$Busy,
    [string]$StatusKey
  )

  $script:statusKey = $StatusKey
  $statusLabel.Text = Get-CinderellaText $script:statusKey
  $progressBar.Visible = $Busy
  $progressBar.Style = if ($Busy) {
    [System.Windows.Forms.ProgressBarStyle]::Marquee
  } else {
    [System.Windows.Forms.ProgressBarStyle]::Blocks
  }
  $form.UseWaitCursor = $Busy
  $scanButton.Enabled = -not $Busy
  $planButton.Enabled = -not $Busy
  $actionButton.Enabled = (-not $Busy) -and ($script:planItems.Count -gt 0)
  $languageToggle.Enabled = -not $Busy
  $form.Refresh()
  [System.Windows.Forms.Application]::DoEvents()
}

function Start-CinderellaJob {
  param(
    [ValidateSet("Scan", "Candidates", "Action")]
    [string]$Operation,
    $Payload = $null,
    [string]$StatusKey
  )

  if ($script:activeJob) {
    return
  }

  Set-CinderellaBusy -Busy $true -StatusKey $StatusKey
  $script:activeOperation = $Operation
  $corePath = Join-Path $PSScriptRoot "Cinderella.Core.ps1"
  $script:activeJob = Start-Job -ArgumentList $corePath, $ConfigPath, $Operation, $Payload -ScriptBlock {
    param($CorePath, $ConfigPath, $Operation, $Payload)

    . $CorePath
    $config = Read-CinderellaConfig $ConfigPath

    switch ($Operation) {
      "Scan" {
        Invoke-CinderellaScan $config
      }
      "Candidates" {
        Invoke-CinderellaPlan (Invoke-CinderellaScan $config)
      }
      "Action" {
        Invoke-CinderellaAction -PlanItems $Payload -Config $config -ConfirmAction
      }
    }
  }
  $jobTimer.Start()
}

function Complete-CinderellaJob {
  if (-not $script:activeJob -or $script:activeJob.State -eq "Running") {
    return
  }

  $job = $script:activeJob
  $operation = $script:activeOperation
  $script:activeJob = $null
  $script:activeOperation = ""
  $jobTimer.Stop()

  try {
    if ($job.State -eq "Failed") {
      $jobError = ($job.ChildJobs | ForEach-Object { $_.JobStateInfo.Reason.Message }) -join "`n"
      if ([string]::IsNullOrWhiteSpace($jobError)) {
        $jobError = "Background job failed."
      }
      throw $jobError
    }

    $items = @(Receive-Job -Job $job -ErrorAction Stop)
    switch ($operation) {
      "Scan" {
        $script:scanItems = $items
        $script:planItems = @()
        Set-CinderellaGrid -Grid $grid -Items $script:scanItems -Selectable $false
        Set-CinderellaBusy -Busy $false -StatusKey "scanDone"
        $actionButton.Enabled = $false
      }
      "Candidates" {
        $script:planItems = $items
        Set-CinderellaGrid -Grid $grid -Items $script:planItems -Selectable $true
        Set-CinderellaBusy -Busy $false -StatusKey "planReady"
        $actionButton.Enabled = $script:planItems.Count -gt 0
      }
      "Action" {
        Set-CinderellaGrid -Grid $grid -Items $items -Selectable $false
        Set-CinderellaBusy -Busy $false -StatusKey "actionDone"
        $actionButton.Enabled = $false
      }
    }
  } catch {
    Set-CinderellaBusy -Busy $false -StatusKey "ready"
    $titleKey = switch ($operation) {
      "Scan" { "scanFailed" }
      "Candidates" { "planFailed" }
      "Action" { "actionFailed" }
      default { "actionFailed" }
    }
    [System.Windows.Forms.MessageBox]::Show([string]$_.Exception.Message, (Get-CinderellaText $titleKey), "OK", "Error") | Out-Null
  } finally {
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
  }
}

function Get-SelectedPlanItems {
  param($Grid)

  $Grid.EndEdit()
  $selected = @()
  foreach ($row in $Grid.Rows) {
    if ($row.IsNewRow) {
      continue
    }

    if ([bool]$row.Cells["selected"].Value) {
      $index = [int]$row.Cells["itemIndex"].Value
      $selected += $script:planItems[$index]
    }
  }

  return $selected
}

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = [System.Windows.Forms.Form]::new()
$form.Text = Get-CinderellaText "title"
$form.StartPosition = "CenterScreen"
$form.Size = [System.Drawing.Size]::new(1100, 680)
$form.MinimumSize = [System.Drawing.Size]::new(900, 520)

$title = [System.Windows.Forms.Label]::new()
$title.Text = Get-CinderellaText "title"
$title.Font = [System.Drawing.Font]::new("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = [System.Drawing.Point]::new(16, 14)

$description = [System.Windows.Forms.Label]::new()
$description.Text = Get-CinderellaText "description"
$description.Font = [System.Drawing.Font]::new("Segoe UI", 10)
$description.AutoSize = $true
$description.Location = [System.Drawing.Point]::new(18, 52)

$scanButton = [System.Windows.Forms.Button]::new()
$scanButton.Text = Get-CinderellaText "scan"
$scanButton.Size = [System.Drawing.Size]::new(120, 34)
$scanButton.Location = [System.Drawing.Point]::new(18, 86)

$planButton = [System.Windows.Forms.Button]::new()
$planButton.Text = Get-CinderellaText "plan"
$planButton.Size = [System.Drawing.Size]::new(120, 34)
$planButton.Location = [System.Drawing.Point]::new(148, 86)

$actionButton = [System.Windows.Forms.Button]::new()
$actionButton.Text = Get-CinderellaText "action"
$actionButton.Size = [System.Drawing.Size]::new(140, 34)
$actionButton.Location = [System.Drawing.Point]::new(278, 86)
$actionButton.Enabled = $false

$closeButton = [System.Windows.Forms.Button]::new()
$closeButton.Text = Get-CinderellaText "close"
$closeButton.Size = [System.Drawing.Size]::new(120, 34)
$closeButton.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$closeButton.Location = [System.Drawing.Point]::new(946, 86)

$languageToggle = [System.Windows.Forms.ComboBox]::new()
$languageToggle.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$languageToggle.Items.AddRange(@("한국어", "English"))
$languageToggle.SelectedIndex = 0
$languageToggle.Size = [System.Drawing.Size]::new(120, 28)
$languageToggle.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$languageToggle.Location = [System.Drawing.Point]::new(946, 52)

$statusLabel = [System.Windows.Forms.Label]::new()
$statusLabel.Text = Get-CinderellaText $script:statusKey
$statusLabel.AutoSize = $true
$statusLabel.Location = [System.Drawing.Point]::new(18, 128)

$progressBar = [System.Windows.Forms.ProgressBar]::new()
$progressBar.Size = [System.Drawing.Size]::new(260, 14)
$progressBar.Location = [System.Drawing.Point]::new(18, 142)
$progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
$progressBar.MarqueeAnimationSpeed = 28
$progressBar.Visible = $false

$grid = [System.Windows.Forms.DataGridView]::new()
$grid.Location = [System.Drawing.Point]::new(18, 164)
$grid.Size = [System.Drawing.Size]::new(1048, 460)
$grid.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
$grid.AutoSizeRowsMode = [System.Windows.Forms.DataGridViewAutoSizeRowsMode]::DisplayedCells
$grid.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$grid.MultiSelect = $false
$grid.RowHeadersVisible = $false
$grid.DefaultCellStyle.WrapMode = [System.Windows.Forms.DataGridViewTriState]::False

$selectedColumn = [System.Windows.Forms.DataGridViewCheckBoxColumn]::new()
$selectedColumn.Name = "selected"
$selectedColumn.HeaderText = if ($script:language -eq "ko") { "실행" } else { "Run" }
$selectedColumn.Width = 72
$grid.Columns.Add($selectedColumn) | Out-Null

$columnHeaders = Get-CinderellaColumnHeaders

foreach ($columnName in @("module", "name", "status", "action", "itemCount", "sizeBytes", "path", "note")) {
  $column = [System.Windows.Forms.DataGridViewTextBoxColumn]::new()
  $column.Name = $columnName
  $column.HeaderText = $columnHeaders[$columnName]
  $column.ReadOnly = $true
  $column.Width = switch ($columnName) {
    "module" { 190 }
    "name" { 240 }
    "status" { 150 }
    "action" { 240 }
    "itemCount" { 90 }
    "sizeBytes" { 110 }
    "path" { 520 }
    "note" { 520 }
    default { 140 }
  }
  $grid.Columns.Add($column) | Out-Null
}

$indexColumn = [System.Windows.Forms.DataGridViewTextBoxColumn]::new()
$indexColumn.Name = "itemIndex"
$indexColumn.HeaderText = "itemIndex"
$indexColumn.Visible = $false
$grid.Columns.Add($indexColumn) | Out-Null

$jobTimer = [System.Windows.Forms.Timer]::new()
$jobTimer.Interval = 250
$jobTimer.Add_Tick({ Complete-CinderellaJob })

function Update-CinderellaLanguage {
  $form.Text = Get-CinderellaText "title"
  $title.Text = Get-CinderellaText "title"
  $description.Text = Get-CinderellaText "description"
  $scanButton.Text = Get-CinderellaText "scan"
  $planButton.Text = Get-CinderellaText "plan"
  $actionButton.Text = Get-CinderellaText "action"
  $closeButton.Text = Get-CinderellaText "close"
  $statusLabel.Text = Get-CinderellaText $script:statusKey

  $headers = Get-CinderellaColumnHeaders
  $grid.Columns["selected"].HeaderText = if ($script:language -eq "ko") { "실행" } else { "Run" }
  foreach ($columnName in $headers.Keys) {
    $grid.Columns[$columnName].HeaderText = $headers[$columnName]
  }

  if ($script:currentItems.Count -gt 0) {
    $selectedIndexes = if ($script:currentSelectable) {
      $checked = @(Get-CheckedIndexes -Grid $grid)
      if ($checked.Count -eq 0) { @(-1) } else { $checked }
    } else {
      @()
    }
    Set-CinderellaGrid -Grid $grid -Items $script:currentItems -Selectable $script:currentSelectable -SelectedIndexes $selectedIndexes
  }
}

$scanButton.Add_Click({
  Start-CinderellaJob -Operation "Scan" -StatusKey "scanning"
})

$planButton.Add_Click({
  if ($script:scanItems.Count -gt 0) {
    Set-CinderellaBusy -Busy $true -StatusKey "planning"
    $script:planItems = @(Invoke-CinderellaPlan $script:scanItems)
    Set-CinderellaGrid -Grid $grid -Items $script:planItems -Selectable $true
    Set-CinderellaBusy -Busy $false -StatusKey "planReady"
    $actionButton.Enabled = $script:planItems.Count -gt 0
    return
  }

  Start-CinderellaJob -Operation "Candidates" -StatusKey "planning"
})

$actionButton.Add_Click({
  try {
    $selectedItems = @(Get-SelectedPlanItems -Grid $grid)
    if ($selectedItems.Count -eq 0) {
      [System.Windows.Forms.MessageBox]::Show((Get-CinderellaText "noSelection"), (Get-CinderellaText "noSelectionTitle"), "OK", "Information") | Out-Null
      return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
      ((Get-CinderellaText "confirmTemplate") -f $selectedItems.Count),
      (Get-CinderellaText "confirmTitle"),
      "OKCancel",
      "Warning"
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::OK) {
      return
    }

    Start-CinderellaJob -Operation "Action" -Payload $selectedItems -StatusKey "actionRunning"
  } catch {
    Set-CinderellaBusy -Busy $false -StatusKey "ready"
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, (Get-CinderellaText "actionFailed"), "OK", "Error") | Out-Null
  }
})

$languageToggle.Add_SelectedIndexChanged({
  $script:language = if ($languageToggle.SelectedIndex -eq 0) { "ko" } else { "en" }
  Update-CinderellaLanguage
})

$form.Add_FormClosing({
  if ($script:activeJob) {
    Stop-Job -Job $script:activeJob -ErrorAction SilentlyContinue
    Remove-Job -Job $script:activeJob -Force -ErrorAction SilentlyContinue
    $script:activeJob = $null
  }
})

$closeButton.Add_Click({ $form.Close() })

$form.Controls.AddRange(@(
  $title,
  $description,
  $scanButton,
  $planButton,
  $actionButton,
  $closeButton,
  $languageToggle,
  $statusLabel,
  $progressBar,
  $grid
))

[System.Windows.Forms.Application]::Run($form)




