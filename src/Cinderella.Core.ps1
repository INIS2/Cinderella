Set-StrictMode -Version Latest

function Read-CinderellaConfig {
  param([string]$Path)

  $resolvedPath = Resolve-Path -LiteralPath $Path
  return Get-Content -Raw -Encoding UTF8 -LiteralPath $resolvedPath | ConvertFrom-Json
}

function Expand-CinderellaPath {
  param([string]$Path)

  return [Environment]::ExpandEnvironmentVariables($Path)
}

function New-CinderellaItem {
  param(
    [string]$Module,
    [string]$Name,
    [string]$Status,
    [string]$Action,
    [string]$Path = "",
    [string]$Note = "",
    [long]$ItemCount = 0,
    [long]$SizeBytes = 0,
    [bool]$AllowRoot = $false
  )

  [pscustomobject]@{
    module = $Module
    name = $Name
    status = $Status
    action = $Action
    path = $Path
    note = $Note
    itemCount = $ItemCount
    sizeBytes = $SizeBytes
    allowRoot = $AllowRoot
  }
}

function New-CinderellaResult {
  param(
    [string]$Module,
    [string]$Name,
    [string]$Status,
    [string]$Message
  )

  [pscustomobject]@{
    module = $Module
    name = $Name
    status = $Status
    action = ""
    path = ""
    note = $Message
    itemCount = 0
    sizeBytes = 0
    allowRoot = $false
    message = $Message
  }
}

function Test-SafeCleanupPath {
  param(
    [string]$Path,
    [bool]$AllowRoot = $false
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $false
  }

  $rootedPath = [System.IO.Path]::GetFullPath($Path)
  $rootPath = [System.IO.Path]::GetPathRoot($rootedPath)
  if ((-not $AllowRoot) -and $rootedPath.TrimEnd("\") -ieq $rootPath.TrimEnd("\")) {
    return $false
  }

  $blocked = @(
    [Environment]::GetFolderPath("Windows"),
    [Environment]::GetFolderPath("ProgramFiles"),
    [Environment]::GetFolderPath("ProgramFilesX86"),
    [Environment]::GetFolderPath("UserProfile")
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  return -not ($blocked | Where-Object {
    $rootedPath.TrimEnd("\") -ieq ([System.IO.Path]::GetFullPath($_)).TrimEnd("\")
  })
}

function Get-CinderellaPathStats {
  param(
    [string]$Path,
    [string]$ExcludePath = ""
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return [pscustomobject]@{ itemCount = 0; sizeBytes = 0 }
  }

  $count = 0L
  $bytes = 0L
  $excludeFullPath = if ([string]::IsNullOrWhiteSpace($ExcludePath)) {
    ""
  } else {
    [System.IO.Path]::GetFullPath($ExcludePath).TrimEnd("\")
  }

  Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $fullName = [System.IO.Path]::GetFullPath($_.FullName).TrimEnd("\")
    if ($excludeFullPath -and ($fullName -ieq $excludeFullPath -or $fullName.StartsWith("$excludeFullPath\", [System.StringComparison]::OrdinalIgnoreCase))) {
      return
    }

    $count++
    if (-not $_.PSIsContainer) {
      $bytes += [int64]$_.Length
    }
  }

  return [pscustomobject]@{ itemCount = $count; sizeBytes = $bytes }
}

function Format-CinderellaSize {
  param([long]$Bytes)

  if ($Bytes -ge 1GB) {
    return "{0:N2} GB" -f ($Bytes / 1GB)
  }
  if ($Bytes -ge 1MB) {
    return "{0:N2} MB" -f ($Bytes / 1MB)
  }
  if ($Bytes -ge 1KB) {
    return "{0:N2} KB" -f ($Bytes / 1KB)
  }

  return "$Bytes B"
}

function Get-DriveFreeBytes {
  param([string]$Path)

  $expandedPath = [Environment]::ExpandEnvironmentVariables($Path)
  $root = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($expandedPath))
  if ([string]::IsNullOrWhiteSpace($root)) {
    return 0L
  }

  $drive = [System.IO.DriveInfo]::new($root)
  return [int64]$drive.AvailableFreeSpace
}

function Test-ProcessRunning {
  param([string[]]$ProcessNames)

  foreach ($processName in $ProcessNames) {
    if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
      return $true
    }
  }

  return $false
}

function Test-CinderellaAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-CinderellaReportRoot {
  param($Config)

  $root = if ($Config.mvp.report.enabled -and -not [string]::IsNullOrWhiteSpace($Config.mvp.report.root)) {
    $Config.mvp.report.root
  } else {
    ".\reports"
  }

  if ([System.IO.Path]::IsPathRooted($root)) {
    return [Environment]::ExpandEnvironmentVariables($root)
  }

  return Join-Path (Split-Path -Parent $PSScriptRoot) $root
}

function Save-CinderellaReport {
  param(
    $Config,
    $PlanItems,
    $Results
  )

  if (-not $Config.mvp.report.enabled) {
    return ""
  }

  $reportRoot = Resolve-CinderellaReportRoot $Config
  New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
  $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $reportPath = Join-Path $reportRoot "cinderella_$timestamp.json"
  $report = [pscustomobject]@{
    timestamp = (Get-Date).ToString("o")
    computerName = $env:COMPUTERNAME
    userName = $env:USERNAME
    plan = $PlanItems
    results = $Results
  }
  $report | ConvertTo-Json -Depth 8 | Set-Content -Path $reportPath -Encoding UTF8

  return $reportPath
}

function Get-WindowsUpdateScan {
  param($Config)

  if (-not $Config.mvp.windowsUpdate.enabled) {
    return @()
  }

  $service = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
  $status = if ($service) { [string]$service.Status } else { "NotFound" }
  $currentVersion = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
  $versionNote = if ($currentVersion) {
    "Windows $($currentVersion.DisplayVersion), build $($currentVersion.CurrentBuild).$($currentVersion.UBR)"
  } else {
    "Windows version info unavailable."
  }
  $latestHotfix = try {
    Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Select-Object -First 1
  } catch {
    $null
  }
  if ($latestHotfix) {
    $versionNote = "$versionNote Latest hotfix: $($latestHotfix.HotFixID) ($($latestHotfix.InstalledOn.ToShortDateString()))."
  }

  $updateCount = 0
  $updateStatus = "Unknown"
  $updateNote = $versionNote
  try {
    $session = New-Object -ComObject "Microsoft.Update.Session"
    $searcher = $session.CreateUpdateSearcher()
    $searchResult = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
    $updateCount = [int]$searchResult.Updates.Count
    $updateStatus = if ($updateCount -gt 0) { "NeedsAction" } else { "Latest" }
    $updateNote = "$versionNote Available update(s): $updateCount."
  } catch {
    $updateStatus = "CheckFailed"
    $updateNote = "$versionNote Update check failed: $($_.Exception.Message)"
  }

  return @(
    New-CinderellaItem `
      -Module "WindowsUpdate" `
      -Name "Windows Update" `
      -Status $updateStatus `
      -Action $(if ($updateCount -gt 0) { "Open Windows Update settings" } else { "Skip" }) `
      -Note "Service: $status. $updateNote" `
      -ItemCount $updateCount
  )
}

function Get-PrivilegeScan {
  $isAdmin = Test-CinderellaAdministrator
  return @(
    New-CinderellaItem `
      -Module "Privilege" `
      -Name "Administrator rights" `
      -Status $(if ($isAdmin) { "Admin" } else { "Standard" }) `
      -Action "Skip" `
      -Note $(if ($isAdmin) { "Running with administrator rights." } else { "Some actions may fail without administrator rights." })
  )
}

function Get-BrowserCleanupScan {
  param($Config)

  if (-not $Config.mvp.browserCleanup.enabled) {
    return @()
  }

  $items = @()
  foreach ($browser in $Config.mvp.browserCleanup.browsers) {
    $profileRoot = Expand-CinderellaPath $browser.profileRoot
    $isRunning = Test-ProcessRunning -ProcessNames $browser.processNames

    foreach ($relativeTarget in $Config.mvp.browserCleanup.relativeTargets) {
      $targetPath = Join-Path $profileRoot $relativeTarget
      $exists = Test-Path -LiteralPath $targetPath
      $stats = Get-CinderellaPathStats -Path $targetPath
      $status = if ($isRunning) { "Blocked" } elseif ($exists) { "Found" } else { "Missing" }
      $action = if ($isRunning -or -not $exists) { "Skip" } else { "Clean target" }
      $note = if ($isRunning) {
        "$($browser.name) is running. Close it before cleanup."
      } elseif ($exists) {
        "$($stats.itemCount) item(s), $(Format-CinderellaSize $stats.sizeBytes)."
      } else {
        ""
      }
      $items += New-CinderellaItem `
        -Module "BrowserCleanup" `
        -Name "$($browser.name): $relativeTarget" `
        -Status $status `
        -Action $action `
        -Path $targetPath `
        -Note $note `
        -ItemCount $stats.itemCount `
        -SizeBytes $stats.sizeBytes
    }
  }

  return $items
}

function Get-FileCleanupScan {
  param($Config)

  if (-not $Config.mvp.fileCleanup.enabled) {
    return @()
  }

  $items = @()
  foreach ($target in $Config.mvp.fileCleanup.targets) {
    $targetPath = Expand-CinderellaPath $target.path
    $targetName = if ($target.name) { $target.name } else { $targetPath }
    $allowRoot = [bool]$target.allowRoot
    $exists = Test-Path -LiteralPath $targetPath
    $safe = Test-SafeCleanupPath -Path $targetPath -AllowRoot $allowRoot
    $quarantineRoot = Expand-CinderellaPath $Config.mvp.fileCleanup.quarantineRoot
    $stats = Get-CinderellaPathStats -Path $targetPath -ExcludePath $quarantineRoot
    $hasQuarantineSpace = $true
    if ($Config.mvp.fileCleanup.mode -eq "quarantine") {
      $hasQuarantineSpace = (Get-DriveFreeBytes $quarantineRoot) -gt $stats.sizeBytes
    }

    $isReady = $exists -and $safe -and $hasQuarantineSpace
    $note = if (-not $safe) {
      "Blocked by safety guard."
    } elseif (-not $hasQuarantineSpace) {
      "Blocked: quarantine drive does not have enough free space for $(Format-CinderellaSize $stats.sizeBytes)."
    } elseif ($exists) {
      "$($stats.itemCount) item(s), $(Format-CinderellaSize $stats.sizeBytes). Mode: $($Config.mvp.fileCleanup.mode)."
    } else {
      ""
    }
    $items += New-CinderellaItem `
      -Module "FileCleanup" `
      -Name $targetName `
      -Status $(if ($isReady) { "Ready" } elseif ($exists) { "Blocked" } else { "Missing" }) `
      -Action $(if ($isReady) { "Clean children" } else { "Skip" }) `
      -Path $targetPath `
      -Note $note `
      -ItemCount $stats.itemCount `
      -SizeBytes $stats.sizeBytes `
      -AllowRoot $allowRoot
  }

  return $items
}

function Get-RecycleBinScan {
  param($Config)

  if (-not $Config.mvp.recycleBin.enabled) {
    return @()
  }

  return @(
    New-CinderellaItem `
      -Module "RecycleBin" `
      -Name "Recycle Bin" `
      -Status "Available" `
      -Action "Empty recycle bin"
  )
}

function Get-FutureSlotScan {
  param($Config)

  return @(
    New-CinderellaItem -Module "Future" -Name "Desktop icons and shortcuts" -Status "Reserved" -Action "Not implemented"
    New-CinderellaItem -Module "Future" -Name "Registry/environment audit" -Status "Reserved" -Action "Not implemented"
    New-CinderellaItem -Module "Future" -Name "Installed program audit" -Status "Reserved" -Action "Not implemented"
    New-CinderellaItem -Module "Future" -Name "Detailed report" -Status "Reserved" -Action "Not implemented"
  )
}

function Invoke-CinderellaScan {
  param($Config)

  @(
    Get-PrivilegeScan
    Get-WindowsUpdateScan $Config
    Get-BrowserCleanupScan $Config
    Get-FileCleanupScan $Config
    Get-RecycleBinScan $Config
    Get-FutureSlotScan $Config
  )
}

function Invoke-CinderellaPlan {
  param($ScanItems)

  $ScanItems | Where-Object {
    $_.action -ne "Skip" -and $_.action -ne "Not implemented"
  }
}

function Invoke-CinderellaAction {
  param(
    $PlanItems,
    $Config,
    [switch]$ConfirmAction
  )

  if (-not $ConfirmAction) {
    throw "Action stage requires -ConfirmAction. Run Plan first and review the targets."
  }

  $results = @()
  foreach ($item in $PlanItems) {
    switch ($item.module) {
      "WindowsUpdate" {
        Start-Process "ms-settings:windowsupdate"
        $results += New-CinderellaResult -Module $item.module -Name $item.name -Status "Started" -Message "Opened Windows Update settings."
      }
      "BrowserCleanup" {
        try {
          if (Test-Path -LiteralPath $item.path) {
            Remove-Item -LiteralPath $item.path -Recurse -Force -ErrorAction Stop
            $results += New-CinderellaResult -Module $item.module -Name $item.name -Status "Done" -Message "Removed target."
          } else {
            $results += New-CinderellaResult -Module $item.module -Name $item.name -Status "Skipped" -Message "Target was missing."
          }
        } catch {
          $results += New-CinderellaResult -Module $item.module -Name $item.name -Status "Failed" -Message $_.Exception.Message
        }
      }
      "FileCleanup" {
        try {
          if ((Test-Path -LiteralPath $item.path) -and (Test-SafeCleanupPath -Path $item.path -AllowRoot $item.allowRoot)) {
            $children = @(Get-ChildItem -LiteralPath $item.path -Force -ErrorAction Stop)
            if ($Config.mvp.fileCleanup.mode -eq "quarantine") {
              $quarantineRoot = Expand-CinderellaPath $Config.mvp.fileCleanup.quarantineRoot
              if ((Get-DriveFreeBytes $quarantineRoot) -lt $item.sizeBytes) {
                $results += New-CinderellaResult -Module $item.module -Name $item.name -Status "Skipped" -Message "Not enough free space in quarantine drive."
                continue
              }

              $quarantinePath = Join-Path $quarantineRoot "$(Get-Date -Format 'yyyyMMdd_HHmmss')_$($item.name -replace '[^\w.-]', '_')"
              New-Item -ItemType Directory -Path $quarantinePath -Force | Out-Null
              $moved = 0
              $failed = 0
              foreach ($child in $children) {
                if ($child.FullName.StartsWith($quarantineRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                  continue
                }
                try {
                  Move-Item -LiteralPath $child.FullName -Destination (Join-Path $quarantinePath $child.Name) -Force -ErrorAction Stop
                  $moved++
                } catch {
                  $failed++
                }
              }
              $status = if ($failed -gt 0) { "Partial" } else { "Done" }
              $results += New-CinderellaResult -Module $item.module -Name $item.name -Status $status -Message "Moved $moved item(s) to quarantine; $failed failed. $quarantinePath"
            } else {
              $removed = 0
              $failed = 0
              foreach ($child in $children) {
                try {
                  Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop
                  $removed++
                } catch {
                  $failed++
                }
              }
              $status = if ($failed -gt 0) { "Partial" } else { "Done" }
              $results += New-CinderellaResult -Module $item.module -Name $item.name -Status $status -Message "Removed $removed item(s); $failed failed."
            }
          } else {
            $results += New-CinderellaResult -Module $item.module -Name $item.name -Status "Skipped" -Message "Target was missing or blocked."
          }
        } catch {
          $results += New-CinderellaResult -Module $item.module -Name $item.name -Status "Failed" -Message $_.Exception.Message
        }
      }
      "RecycleBin" {
        try {
          Clear-RecycleBin -Force -ErrorAction Stop
          $results += New-CinderellaResult -Module $item.module -Name $item.name -Status "Done" -Message "Emptied recycle bin."
        } catch {
          $results += New-CinderellaResult -Module $item.module -Name $item.name -Status "Failed" -Message $_.Exception.Message
        }
      }
      default {
        $results += New-CinderellaResult -Module $item.module -Name $item.name -Status "Skipped" -Message "Module is not implemented."
      }
    }
  }

  $reportPath = Save-CinderellaReport -Config $Config -PlanItems $PlanItems -Results $results
  if ($reportPath) {
    $results += New-CinderellaResult -Module "Report" -Name "JSON report" -Status "Saved" -Message $reportPath
  }

  return $results
}



