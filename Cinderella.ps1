[CmdletBinding()]
param(
    [ValidateSet('interactive', 'scan', 'clean', 'gui', 'help')]
    [string]$Command = 'interactive',
    [switch]$Browser,
    [switch]$Files,
    [switch]$RecycleBin,
    [switch]$All,
    [string[]]$Path = @(),
    [string[]]$Drive = @(),
    [switch]$DryRun,
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:DefaultFolders = @(
    [Environment]::GetFolderPath('UserProfile') + '\Downloads',
    [Environment]::GetFolderPath('MyDocuments'),
    [Environment]::GetFolderPath('MyPictures'),
    [Environment]::GetFolderPath('MyVideos')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$Script:SelectedDrives = @()
$Script:SelectedBrowserProfiles = @()
$Script:BrowserProfilesExplicit = $false
$Script:Language = 'EN'
$Script:Text = @{
    EN = @{
        Title = 'Cinderella'; Subtitle = 'Reset temporary user traces';
        ChooseLanguage = 'Language [KR/EN]'; ChooseMode = 'Mode [CLI/GUI]';
        Check = 'Check'; Go = 'Go'; Targets = 'Targets'; Execution = 'Execution'; Options = 'Options'; Preview = 'Cleanup preview'; CleanupWindow = 'browser cleanup window'; BrowserMissing = 'browser not installed'; BrowserRunning = 'is running. Close it to open every profile cleanup window.'; Recycle = 'Recycle Bin'; Estimated = 'Estimated removable data'; DryRun = 'Dry run complete. Nothing was deleted.'; ProfilePrompt = 'Profile numbers (comma-separated, blank = none)'; DrivePrompt = 'Drive letters (comma-separated, e.g. D:,E:)'; GoConfirm = 'Go Clean'; BrowserOpened = 'Browser windows opened'; FoldersProcessed = 'Folders processed'; RecycleStatus = 'Recycle Bin'; Opened = '[opened]'; Ok = '[ok]';
        DefaultExecution = 'Default execution'; OptionExecution = 'Option execution';
        BrowserDefault = 'Browser: Default'; BrowserAdvanced = 'Browser: Advanced';
        FilesDefault = 'Files: Default'; FilesAdvanced = 'Files: Advanced';
        RecycleDefault = 'Recycle Bin: Default'; GoClean = 'Go Clean';
        Result = 'Result'; EndClose = 'End & Close'; CleanSelected = 'Clean selected items';
        Review = 'Review runs before cleaning.'; NoDrives = 'No additional disks detected.';
        Confirm = 'Browser cleanup windows will open. Selected files and the recycle bin may be cleared. Continue?';
        Done = 'Done. Browser cleanup windows are ready for confirmation.'
    }
    KR = @{
        Title = '신데렐라'; Subtitle = '임시 사용자 흔적 정리';
        ChooseLanguage = '언어 [KR/EN]'; ChooseMode = '모드 [CLI/GUI]';
        Check = '확인'; Go = '진행'; Targets = '대상'; Execution = '시행'; Options = '옵션'; Preview = '정리 미리 보기'; CleanupWindow = '브라우저 정리창'; BrowserMissing = '브라우저가 설치되지 않았습니다'; BrowserRunning = '실행 중입니다. 모든 프로필 정리창을 열려면 먼저 닫아주세요.'; Recycle = '휴지통'; Estimated = '예상 정리 용량'; DryRun = '미리 보기 완료. 삭제하지 않았습니다.'; ProfilePrompt = '프로필 번호를 쉼표로 입력하세요 (빈칸 = 없음)'; DrivePrompt = '드라이브 문자를 쉼표로 입력하세요 (예: D:,E:)'; GoConfirm = '정리 실행'; BrowserOpened = '열린 브라우저 정리창'; FoldersProcessed = '처리한 폴더'; RecycleStatus = '휴지통'; Opened = '[열림]'; Ok = '[완료]';
        DefaultExecution = '기본 시행'; OptionExecution = '옵션 시행';
        BrowserDefault = '브라우저: 기본'; BrowserAdvanced = '브라우저: 고급';
        FilesDefault = '파일: 기본'; FilesAdvanced = '파일: 고급';
        RecycleDefault = '휴지통: 기본'; GoClean = '정리 실행';
        Result = '결과'; EndClose = '종료'; CleanSelected = '선택 항목 정리';
        Review = '정리 전에 검토합니다.'; NoDrives = '추가 디스크가 없습니다.';
        Confirm = '브라우저 정리창이 열립니다. 선택한 파일과 휴지통을 정리할 수 있습니다. 계속할까요?';
        Done = '완료되었습니다. 브라우저 정리창에서 삭제를 확인하세요.'
    }
}

function T([string]$Key) {
    return $Script:Text[$Script:Language][$Key]
}

function Set-FlowSelection([bool]$UseBrowser, [bool]$UseFiles, [bool]$UseRecycleBin) {
    $script:Browser = $UseBrowser
    $script:Files = $UseFiles
    $script:RecycleBin = $UseRecycleBin
    $script:All = $false
}

function Set-DefaultFlowSelection {
    $script:SelectedDrives = @()
    $script:SelectedBrowserProfiles = @()
    $script:BrowserProfilesExplicit = $false
    Set-FlowSelection $true $true $true
}

function Write-Title {
    Write-Host ''
    Write-Host ("  * {0}" -f (T 'Title')) -ForegroundColor Magenta
    Write-Host ("    {0}" -f (T 'Subtitle')) -ForegroundColor DarkGray
    Write-Host ''
}

function Format-Bytes([long]$Bytes) {
    if ($Bytes -lt 1KB) { return "$Bytes B" }
    $units = 'KB', 'MB', 'GB', 'TB'
    $value = [double]$Bytes / 1KB
    foreach ($unit in $units) {
        if ($value -lt 1024 -or $unit -eq 'TB') { return ('{0:N1} {1}' -f $value, $unit) }
        $value /= 1024
    }
}

function Get-SelectedOptions {
    $useBrowser = $Browser -or $All
    $useFiles = $Files -or $All
    $useRecycleBin = $RecycleBin -or $All
    if (-not ($useBrowser -or $useFiles -or $useRecycleBin)) {
        $useBrowser = $true; $useFiles = $true; $useRecycleBin = $true
    }
    [pscustomobject]@{ Browser = $useBrowser; Files = $useFiles; RecycleBin = $useRecycleBin }
}

function Get-CleanupFolders {
    $folders = [System.Collections.Generic.List[string]]::new()
    $Script:DefaultFolders | ForEach-Object { $folders.Add($_) }
    $Path | ForEach-Object {
        if ($_ -and (Test-Path -LiteralPath $_ -PathType Container)) { $folders.Add((Resolve-Path -LiteralPath $_).Path) }
        elseif ($_){ Write-Warning "Skipping missing folder: $_" }
    }
    $selectedDrives = @($Drive) + @($Script:SelectedDrives)
    foreach ($drive in ($selectedDrives | Where-Object { $_ } | Select-Object -Unique)) {
        $root = if ($drive -match '^[A-Za-z]:\\?$') { '{0}:\' -f $drive.Substring(0, 1) } else { $drive }
        if (Test-Path -LiteralPath $root -PathType Container) { $folders.Add((Resolve-Path -LiteralPath $root).Path) }
        else { Write-Warning "Skipping missing drive: $drive" }
    }
    return $folders | Select-Object -Unique
}

function Get-AdditionalDrives {
    $drives = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3" -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceID -and $_.DeviceID -ne $env:SystemDrive } |
        ForEach-Object {
            [pscustomobject]@{ Name = $_.DeviceID; Label = $_.VolumeName; Size = [long]$_.Size; Free = [long]$_.FreeSpace }
        })
    if (-not $drives.Count) {
        $drives = @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Name -ne $env:SystemDrive.TrimEnd(':') } |
            ForEach-Object { [pscustomobject]@{ Name = "$($_.Name):"; Label = $_.Description; Size = [long]$_.Used + [long]$_.Free; Free = [long]$_.Free } })
    }
    return $drives
}

function Test-SafeFolder([string]$Folder) {
    $full = [IO.Path]::GetFullPath($Folder).TrimEnd('\')
    $protected = @(
        [Environment]::GetFolderPath('UserProfile'),
        $env:windir,
        ${env:ProgramFiles},
        ${env:ProgramFiles(x86)}
    ) | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') }
    if ($full -eq $env:SystemDrive.TrimEnd('\')) { return $false }
    return -not ($protected -contains $full)
}

function Get-FolderSummary([string]$Folder) {
    $files = @(Get-ChildItem -LiteralPath $Folder -Force -File -Recurse -ErrorAction SilentlyContinue)
    $bytes = if ($files.Count) { ($files | Measure-Object -Property Length -Sum).Sum } else { 0 }
    [pscustomobject]@{ Type = 'Folder'; Name = $Folder; Files = $files.Count; Bytes = [long]$bytes }
}

function Get-BrowserProfiles([string]$Root) {
    if (-not (Test-Path -LiteralPath $Root)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -Force -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
}

function Get-BrowserDefinitions {
    $definitions = @(
        @{ Name = 'Chrome'; Process = 'chrome'; Root = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'); Uri = 'chrome://settings/clearBrowserData'; Candidates = @(
            (Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
            (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
        ) },
        @{ Name = 'Edge'; Process = 'msedge'; Root = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'); Uri = 'edge://settings/clearBrowserData'; Candidates = @(
            (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path ${env:ProgramFiles} 'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe')
        ) }
    )
    foreach ($definition in $definitions) {
        $executable = $definition.Candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
        [pscustomobject]@{
            Name = $definition.Name
            Process = $definition.Process
            Root = $definition.Root
            Uri = $definition.Uri
            Executable = $executable
        }
    }
}

function Get-BrowserSummary {
    foreach ($browser in Get-BrowserDefinitions) {
        foreach ($profile in Get-BrowserProfiles $browser.Root) {
            [pscustomobject]@{
                Type = 'BrowserProfile'
                Name = "$($browser.Name) / $($profile.Name)"
                Browser = $browser.Name
                Process = $browser.Process
                Profile = $profile.Name
                Uri = $browser.Uri
                Executable = $browser.Executable
                Files = 0
                Bytes = 0L
            }
        }
    }
}

function Get-CleanupPlan($Options) {
    $plan = [System.Collections.Generic.List[object]]::new()
    if ($Options.Browser) {
        Get-BrowserSummary | ForEach-Object {
            if (-not $Script:BrowserProfilesExplicit -or $Script:SelectedBrowserProfiles -contains $_.Name) { $plan.Add($_) }
        }
    }
    if ($Options.Files) {
        Get-CleanupFolders | ForEach-Object { $plan.Add((Get-FolderSummary $_)) }
    }
    if ($Options.RecycleBin) { $plan.Add([pscustomobject]@{ Type = 'RecycleBin'; Name = 'Recycle Bin'; Files = 0; Bytes = 0L }) }
    return $plan
}

function Format-PlanLines($Plan) {
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $Plan) {
        if ($item.Type -eq 'BrowserProfile') { $lines.Add("$($item.Name)  | $(T 'CleanupWindow')") }
        elseif ($item.Type -eq 'RecycleBin') { $lines.Add("$(T 'Recycle')  | default") }
        elseif ($Script:Language -eq 'KR') { $lines.Add("$($item.Name)  | $($item.Files)개 파일 | $(Format-Bytes $item.Bytes)") }
        else { $lines.Add("$($item.Name)  | $($item.Files) files | $(Format-Bytes $item.Bytes)") }
    }
    return $lines
}

function Get-SelectionChangeLines {
    $lines = [System.Collections.Generic.List[string]]::new()
    if ($Script:BrowserProfilesExplicit) {
        $browserText = if ($Script:SelectedBrowserProfiles.Count) { $Script:SelectedBrowserProfiles -join ', ' } else { '(none)' }
        $lines.Add("$(T 'BrowserAdvanced'): $browserText")
    }
    else { $lines.Add("$(T 'BrowserDefault'): all detected profiles") }
    if ($Script:SelectedDrives.Count) { $lines.Add("$(T 'FilesAdvanced'): $($Script:SelectedDrives -join ', ')") }
    else { $lines.Add("$(T 'FilesDefault'): Downloads, Documents, Pictures, Videos") }
    $lines.Add((T 'RecycleDefault'))
    return $lines
}

function Show-Plan($Options) {
    $plan = Get-CleanupPlan $Options
    Write-Host ("  {0}" -f (T 'Preview')) -ForegroundColor Cyan
    $total = 0L
    foreach ($item in $plan) {
        if ($item.Type -eq 'BrowserProfile') {
            $status = if ($item.Executable) { T 'CleanupWindow' } else { T 'BrowserMissing' }
            Write-Host ('  {0,-42} {1}' -f $item.Name, $status)
            continue
        }
        if ($item.Type -eq 'RecycleBin') {
            Write-Host ("  {0}                              ready" -f (T 'Recycle'))
            continue
        }
        $total += $item.Bytes
        Write-Host ('  {0,-42} {1,8} files  {2,10}' -f $item.Name, $item.Files, (Format-Bytes $item.Bytes))
    }
    Write-Host ("`n  {0}: {1}`n" -f (T 'Estimated'), (Format-Bytes $total)) -ForegroundColor Green
    return $plan
}

function Remove-Contents([string]$Folder, [switch]$Preview) {
    if (-not (Test-SafeFolder $Folder)) { throw "Protected or root folder rejected: $Folder" }
    $children = @(Get-ChildItem -LiteralPath $Folder -Force -ErrorAction SilentlyContinue)
    if ($Preview) { return }
    $children | Remove-Item -Force -Recurse -ErrorAction Continue
}

function Open-BrowserCleanupWindows([switch]$Preview) {
    if ($Preview) { return }
    $opened = 0
    foreach ($browser in Get-BrowserDefinitions) {
        $profiles = @(Get-BrowserProfiles $browser.Root)
        if ($Script:BrowserProfilesExplicit) { $profiles = @($profiles | Where-Object { $Script:SelectedBrowserProfiles -contains "$($browser.Name) / $($_.Name)" }) }
        if (-not $profiles.Count) { continue }
        if (-not $browser.Executable) {
            Write-Warning "$($browser.Name): $(T 'BrowserMissing')"
            continue
        }
        if (Get-Process -Name $browser.Process -ErrorAction SilentlyContinue) {
            Write-Warning "$($browser.Name) $(T 'BrowserRunning')"
            continue
        }
        foreach ($profile in $profiles) {
            $profileArgument = '--profile-directory="{0}"' -f $profile.Name
            Start-Process -FilePath $browser.Executable -ArgumentList @($profileArgument, $browser.Uri)
            Write-Host ("  {0} {1} / {2}" -f (T 'Opened'), $browser.Name, $profile.Name) -ForegroundColor Green
            $opened++
        }
    }
    return $opened
}

function Invoke-Cinderella([switch]$Preview, [switch]$SkipPlan) {
    $options = Get-SelectedOptions
    if (-not $SkipPlan) { $null = Show-Plan $options }
    if ($Preview) { Write-Host ("  {0}" -f (T 'DryRun')) -ForegroundColor Yellow; return }
    $opened = if ($options.Browser) { [int](Open-BrowserCleanupWindows) } else { 0 }
    $deletedFolders = [System.Collections.Generic.List[string]]::new()
    if ($options.Files) {
        foreach ($folder in Get-CleanupFolders) {
            Remove-Contents $folder
            $deletedFolders.Add($folder)
            Write-Host ("  {0} $folder" -f (T 'Ok')) -ForegroundColor Green
        }
    }
    $recycleCleared = $false
    if ($options.RecycleBin) {
        Clear-RecycleBin -Force -ErrorAction Stop
        $recycleCleared = $true
        Write-Host ("  {0} {1}" -f (T 'Ok'), (T 'Recycle')) -ForegroundColor Green
    }
    $Script:RunResult = [pscustomobject]@{ BrowserOpened = $opened; Folders = @($deletedFolders); RecycleBin = $recycleCleared }
    Write-Host ("`n  {0}" -f (T 'Done')) -ForegroundColor Green
}

function Start-CliFlow {
    Write-Title
    Set-DefaultFlowSelection
    $go = (Read-Host ("{0} [Go/Cancel]" -f (T 'Check'))).Trim().ToLowerInvariant()
    if ($go -notmatch '^(go|g|진행)$') { return }
    Write-Host "`n  $(T 'Targets')" -ForegroundColor Cyan
    $options = Get-SelectedOptions
    $null = Show-Plan $options
    $execution = (Read-Host "`n[$(T 'DefaultExecution') / $(T 'OptionExecution')] [D/O]").Trim().ToUpperInvariant()
    if ($execution -eq 'D') {
        Set-DefaultFlowSelection
    }
    else {
        $browserMode = (Read-Host "$(T 'BrowserDefault') / $(T 'BrowserAdvanced') [D/A]").Trim().ToUpperInvariant()
        if ($browserMode -eq 'A') {
            $profiles = @(Get-BrowserSummary | Select-Object -ExpandProperty Name)
            for ($index = 0; $index -lt $profiles.Count; $index++) { Write-Host ("  [{0}] {1}" -f ($index + 1), $profiles[$index]) }
            $selected = Read-Host ("  {0}" -f (T 'ProfilePrompt'))
            $script:SelectedBrowserProfiles = @($selected -split ',' | ForEach-Object { $n = 0; if ([int]::TryParse($_.Trim(), [ref]$n) -and $n -gt 0 -and $n -le $profiles.Count) { $profiles[$n - 1] } })
            $script:BrowserProfilesExplicit = $true
        }
        else { $script:SelectedBrowserProfiles = @(); $script:BrowserProfilesExplicit = $false }
        $fileMode = (Read-Host "$(T 'FilesDefault') / $(T 'FilesAdvanced') [D/A]").Trim().ToUpperInvariant()
        $script:SelectedDrives = if ($fileMode -eq 'A') { @((Read-Host ("  {0}" -f (T 'DrivePrompt'))) -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) } else { @() }
        Set-FlowSelection $true $true $true
    }
    Write-Host "`n  $(T 'GoClean')" -ForegroundColor Cyan
    Get-SelectionChangeLines | ForEach-Object { Write-Host "  $_" }
    $confirm = (Read-Host "$(T 'GoClean') [y/N]").Trim()
    if ($confirm -match '^(y|yes|go|진행)$') { Invoke-Cinderella -SkipPlan }
}

function Start-Interactive {
    Write-Title
    $mode = (Read-Host (T 'ChooseMode')).Trim().ToUpperInvariant()
    $language = (Read-Host (T 'ChooseLanguage')).Trim().ToUpperInvariant()
    if ($language -eq 'KR') { $Script:Language = 'KR' } else { $Script:Language = 'EN' }
    if ($mode -eq 'GUI' -or $mode -eq 'G') { Start-Gui -InitialLanguage $Script:Language } else { Start-CliFlow }
}

function Set-GuiVisibility($Control, [bool]$Visible) {
    $Control.Visibility = if ($Visible) { 'Visible' } else { 'Collapsed' }
}

function Start-Gui([string]$InitialLanguage = '') {
    Add-Type -AssemblyName PresentationFramework
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Cinderella" SizeToContent="WidthAndHeight" ResizeMode="NoResize" WindowStartupLocation="CenterScreen" Background="#19151F">
  <StackPanel Margin="26" Width="390">
    <TextBlock x:Name="Title" Text="Cinderella" FontSize="25" FontWeight="SemiBold" Foreground="#F0E9F8" />
    <TextBlock x:Name="Subtitle" Text="Reset temporary user traces" Margin="0,2,0,18" Foreground="#BBAEC8" />
    <StackPanel x:Name="LanguagePanel">
      <TextBlock Text="Language" Foreground="#F0E9F8" Margin="0,4" />
      <StackPanel Orientation="Horizontal">
        <Button x:Name="Kr" Tag="KR" Content="한국어" Margin="0,4,8,12" Padding="12,6" />
        <Button x:Name="En" Tag="EN" Content="English" Margin="0,4,0,12" Padding="12,6" />
      </StackPanel>
    </StackPanel>
    <StackPanel x:Name="CheckPanel" Visibility="Collapsed">
      <TextBlock x:Name="CheckTitle" Text="Check" FontSize="18" Foreground="#F0E9F8" Margin="0,4" />
      <TextBox x:Name="TargetList" IsReadOnly="True" Height="160" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Background="#241D2C" Foreground="#F0E9F8" Padding="8" />
      <Button x:Name="CheckGo" Content="Go" Padding="12,7" Margin="0,12,0,12" />
    </StackPanel>
    <StackPanel x:Name="ExecutionPanel" Visibility="Collapsed">
      <TextBlock x:Name="ExecutionTitle" Text="Execution" FontSize="18" Foreground="#F0E9F8" Margin="0,4" />
      <Button x:Name="DefaultButton" Content="Default execution" Padding="12,7" Margin="0,4" />
      <Button x:Name="OptionsButton" Content="Option execution" Padding="12,7" Margin="0,4,0,12" />
    </StackPanel>
    <StackPanel x:Name="OptionsPanel" Visibility="Collapsed">
      <TextBlock x:Name="OptionsTitle" Text="Options" FontSize="18" Foreground="#F0E9F8" Margin="0,4" />
      <Expander x:Name="BrowserExpander" Header="Browser: Advanced" Foreground="#F0E9F8" Margin="0,4"><StackPanel x:Name="BrowserProfiles" Margin="8" /></Expander>
      <Expander x:Name="FilesExpander" Header="Files: Advanced" Foreground="#F0E9F8" Margin="0,4"><StackPanel x:Name="AdvancedDrives" Margin="8" /></Expander>
      <TextBlock x:Name="RecycleLabel" Text="Recycle Bin: Default" Foreground="#F0E9F8" Margin="0,8" />
      <Button x:Name="OptionsContinue" Content="Go" Padding="12,7" Margin="0,8,0,12" />
    </StackPanel>
    <StackPanel x:Name="GoCleanPanel" Visibility="Collapsed">
      <TextBlock x:Name="GoCleanTitle" Text="Go Clean" FontSize="18" Foreground="#F0E9F8" Margin="0,4" />
      <TextBox x:Name="ChangedList" IsReadOnly="True" Height="130" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Background="#241D2C" Foreground="#F0E9F8" Padding="8" />
      <Button x:Name="GoCleanButton" Content="Go Clean" Padding="12,7" Margin="0,12,0,12" />
    </StackPanel>
    <StackPanel x:Name="ResultPanel" Visibility="Collapsed">
      <TextBlock x:Name="ResultTitle" Text="Result" FontSize="18" Foreground="#F0E9F8" Margin="0,4" />
      <TextBox x:Name="ResultList" IsReadOnly="True" Height="130" TextWrapping="Wrap" Background="#241D2C" Foreground="#F0E9F8" Padding="8" />
      <Button x:Name="EndClose" Content="End &amp; Close" Padding="12,7" Margin="0,12,0,0" />
    </StackPanel>
  </StackPanel>
</Window>
'@
    $window = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($xaml))
    $title = $window.FindName('Title'); $subtitle = $window.FindName('Subtitle'); $languagePanel = $window.FindName('LanguagePanel'); $checkPanel = $window.FindName('CheckPanel'); $executionPanel = $window.FindName('ExecutionPanel'); $optionsPanel = $window.FindName('OptionsPanel'); $goCleanPanel = $window.FindName('GoCleanPanel'); $resultPanel = $window.FindName('ResultPanel')
    $checkTitle = $window.FindName('CheckTitle'); $targetList = $window.FindName('TargetList'); $checkGo = $window.FindName('CheckGo'); $executionTitle = $window.FindName('ExecutionTitle'); $defaultButton = $window.FindName('DefaultButton'); $optionsButton = $window.FindName('OptionsButton'); $optionsTitle = $window.FindName('OptionsTitle'); $browserExpander = $window.FindName('BrowserExpander'); $filesExpander = $window.FindName('FilesExpander'); $browserProfiles = $window.FindName('BrowserProfiles'); $advancedDrives = $window.FindName('AdvancedDrives'); $recycleLabel = $window.FindName('RecycleLabel'); $optionsContinue = $window.FindName('OptionsContinue'); $goCleanTitle = $window.FindName('GoCleanTitle'); $changedList = $window.FindName('ChangedList'); $goCleanButton = $window.FindName('GoCleanButton'); $resultTitle = $window.FindName('ResultTitle'); $resultList = $window.FindName('ResultList'); $endClose = $window.FindName('EndClose')
    $languagePanel.Children[1].Children[0].Add_Click({ $Script:Language = 'KR'; & $render; $languagePanel.Visibility = 'Collapsed'; $checkPanel.Visibility = 'Visible'; $targetList.Text = (Format-PlanLines (Get-CleanupPlan (Get-SelectedOptions))) -join [Environment]::NewLine })
    $languagePanel.Children[1].Children[1].Add_Click({ $Script:Language = 'EN'; & $render; $languagePanel.Visibility = 'Collapsed'; $checkPanel.Visibility = 'Visible'; $targetList.Text = (Format-PlanLines (Get-CleanupPlan (Get-SelectedOptions))) -join [Environment]::NewLine })
    $render = {
        $title.Text = T 'Title'; $subtitle.Text = T 'Subtitle'; $checkTitle.Text = T 'Check'; $checkGo.Content = T 'Go'; $executionTitle.Text = T 'Execution'; $defaultButton.Content = T 'DefaultExecution'; $optionsButton.Content = T 'OptionExecution'; $optionsTitle.Text = T 'Options'; $browserExpander.Header = T 'BrowserAdvanced'; $filesExpander.Header = T 'FilesAdvanced'; $recycleLabel.Text = T 'RecycleDefault'; $optionsContinue.Content = T 'Go'; $goCleanTitle.Text = T 'GoClean'; $goCleanButton.Content = T 'GoClean'; $resultTitle.Text = T 'Result'; $endClose.Content = T 'EndClose'
    }
    $showGoClean = { $goCleanPanel.Visibility = 'Visible'; $resultPanel.Visibility = 'Collapsed'; $changedList.Text = (Get-SelectionChangeLines) -join [Environment]::NewLine }
    $checkGo.Add_Click({ $checkPanel.Visibility = 'Collapsed'; $executionPanel.Visibility = 'Visible' })
    $defaultButton.Add_Click({ Set-DefaultFlowSelection; $executionPanel.Visibility = 'Collapsed'; & $showGoClean })
    $optionsButton.Add_Click({
        $executionPanel.Visibility = 'Collapsed'; $optionsPanel.Visibility = 'Visible'; $Script:SelectedBrowserProfiles = @(); $Script:BrowserProfilesExplicit = $true
        $browserProfiles.Children.Clear(); foreach ($profile in Get-BrowserSummary) { $c = [Windows.Controls.CheckBox]::new(); $c.Content = $profile.Name; $c.Tag = $profile.Name; $c.IsChecked = $true; $c.Foreground = [Windows.Media.Brushes]::WhiteSmoke; $browserProfiles.Children.Add($c) | Out-Null }
        $advancedDrives.Children.Clear(); $drives = @(Get-AdditionalDrives); if (-not $drives.Count) { $c = [Windows.Controls.TextBlock]::new(); $c.Text = T 'NoDrives'; $c.Foreground = [Windows.Media.Brushes]::LightGray; $advancedDrives.Children.Add($c) | Out-Null } else { foreach ($drive in $drives) { $c = [Windows.Controls.CheckBox]::new(); $c.Content = if ($drive.Label) { "$($drive.Name)  $($drive.Label)" } else { $drive.Name }; $c.Tag = $drive.Name; $c.Foreground = [Windows.Media.Brushes]::WhiteSmoke; $advancedDrives.Children.Add($c) | Out-Null } }
    })
    $optionsContinue.Add_Click({ $Script:SelectedBrowserProfiles = @($browserProfiles.Children | Where-Object { $_ -is [Windows.Controls.CheckBox] -and $_.IsChecked } | ForEach-Object { $_.Tag }); $Script:SelectedDrives = @($advancedDrives.Children | Where-Object { $_ -is [Windows.Controls.CheckBox] -and $_.IsChecked } | ForEach-Object { $_.Tag }); Set-FlowSelection $true $true $true; $optionsPanel.Visibility = 'Collapsed'; & $showGoClean })
    $goCleanButton.Add_Click({ $confirm = [System.Windows.MessageBox]::Show((T 'Confirm'), (T 'Title'), 'YesNo', 'Warning'); if ($confirm -ne 'Yes') { return }; try { Invoke-Cinderella -SkipPlan; $goCleanPanel.Visibility = 'Collapsed'; $resultPanel.Visibility = 'Visible'; $resultList.Text = "$(T 'Done')`n$(T 'BrowserOpened'): $($Script:RunResult.BrowserOpened)`n$(T 'FoldersProcessed'): $($Script:RunResult.Folders.Count)`n$(T 'RecycleStatus'): $($Script:RunResult.RecycleBin)" } catch { $resultList.Text = $_.Exception.Message; $goCleanPanel.Visibility = 'Collapsed'; $resultPanel.Visibility = 'Visible' } })
    $endClose.Add_Click({ $window.Close() })
    if ($InitialLanguage -eq 'KR' -or $InitialLanguage -eq 'EN') { $Script:Language = $InitialLanguage; $languagePanel.Visibility = 'Collapsed'; $checkPanel.Visibility = 'Visible'; $targetList.Text = (Format-PlanLines (Get-CleanupPlan (Get-SelectedOptions))) -join [Environment]::NewLine }
    & $render
    $window.ShowDialog() | Out-Null
}

function Show-Help {
@'
Cinderella - small Windows cleanup utility

  Cinderella.ps1 scan
  Cinderella.ps1 clean --dry-run
  Cinderella.ps1 clean --all --yes
  Cinderella.ps1 gui

Options: -Browser -Files -RecycleBin -All -Path <folder> -Drive <letter> -DryRun -Yes
The Cinderella.cmd launcher also accepts long options such as --dry-run, --all, and --drive.

Browser cleanup opens Chrome/Edge's official clear-data page for every detected profile.
The user chooses All time and presses the browser's clear button. Cinderella does not
click that destructive button automatically. Bookmarks, saved passwords, and autofill
data are not selected by this flow.
Additional disks are never selected by default. Choose them explicitly with --drive or in the GUI Advanced section.
'@ | Write-Host
}

switch ($Command) {
    'help' { Show-Help }
    'scan' { Write-Title; Invoke-Cinderella -Preview }
    'clean' {
        Write-Title
        if ($DryRun) { Invoke-Cinderella -Preview }
        elseif ($Yes) { Invoke-Cinderella }
        else { Write-Host '  Add -Yes to confirm permanent deletion, or use -DryRun first.' -ForegroundColor Yellow }
    }
    'gui' { Start-Gui }
    default { Start-Interactive }
}
