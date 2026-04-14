[CmdletBinding()]
param(
  [ValidateSet("Scan", "Plan", "Action")]
  [string]$Stage = "Plan",

  [string]$ConfigPath = "",

  [switch]$ConfirmAction
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Cinderella.Core.ps1")

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
  $ConfigPath = Join-Path $PSScriptRoot "..\config\cinderella.config.json"
}

$config = Read-CinderellaConfig $ConfigPath
$scan = Invoke-CinderellaScan $config

switch ($Stage) {
  "Scan" {
    $scan | Format-Table -AutoSize
  }
  "Plan" {
    Invoke-CinderellaPlan $scan | Format-Table -AutoSize
  }
  "Action" {
    $plan = Invoke-CinderellaPlan $scan
    $plan | Format-Table -AutoSize
    Invoke-CinderellaAction -PlanItems $plan -Config $config -ConfirmAction:$ConfirmAction | Format-Table -AutoSize
  }
}



