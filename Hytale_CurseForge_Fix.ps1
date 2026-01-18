param(
  [switch]$Elevated
)

function Log([string]$msg)  { Write-Host $msg }
function Info([string]$msg) { Write-Host ("[i]  " + $msg) }
function Ok([string]$msg)   { Write-Host ("[OK] " + $msg) -ForegroundColor Green }
function Warn([string]$msg) { Write-Host ("[!]  " + $msg) -ForegroundColor Yellow }
function Err([string]$msg)  { Write-Host ("[X]  " + $msg) -ForegroundColor Red }

function Pause-And-Exit([int]$code) {
  Write-Host ""
  Write-Host "Press Enter to close..." -ForegroundColor DarkGray
  [void](Read-Host)
  exit $code
}

function Is-Admin {
  $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Dir([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
  }
}

function Is-LinkDir([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return $false }
  try {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    return ($null -ne $item.LinkType)
  } catch { return $false }
}

function Unique-Backup-Path([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return $path }

  $dir  = Split-Path -Parent $path
  $leaf = Split-Path -Leaf $path
  $name = [IO.Path]::GetFileNameWithoutExtension($leaf)
  $ext  = [IO.Path]::GetExtension($leaf)

  for ($i=1; $i -le 9999; $i++) {
    $candidate = Join-Path $dir ("{0}.{1}{2}" -f $name, $i, $ext)
    if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
  }
  throw "Could not find a free backup name for: $path"
}

function Merge-Folder-Keep-Newest {
  param(
    [Parameter(Mandatory=$true)][string]$SourceDir,
    [Parameter(Mandatory=$true)][string]$TargetDir,
    [Parameter(Mandatory=$true)][string]$BackupDir,
    [Parameter(Mandatory=$true)][string]$Label
  )

  $stats = [ordered]@{
    Label     = $Label
    Moved     = 0
    Conflicts = 0
    BackedUp  = 0
    KeptDst   = 0
  }

  if (-not (Test-Path -LiteralPath $SourceDir)) {
    Info "${Label}: nothing to merge (source folder not found)."
    return $stats
  }

  $files = Get-ChildItem -LiteralPath $SourceDir -Recurse -File -Force -ErrorAction Stop
  if (-not $files) {
    Info "${Label}: nothing to merge (source folder is empty)."
    return $stats
  }

  Ensure-Dir $TargetDir
  Info "${Label}: merging files (keep newest on conflicts)..."

  foreach ($f in $files) {
    $rel = $f.FullName.Substring($SourceDir.Length).TrimStart('\')
    $tgt = Join-Path $TargetDir $rel
    Ensure-Dir (Split-Path -Parent $tgt)

    if (-not (Test-Path -LiteralPath $tgt)) {
      Move-Item -LiteralPath $f.FullName -Destination $tgt -Force -ErrorAction Stop
      $stats.Moved++
      continue
    }

    $tgtItem = Get-Item -LiteralPath $tgt -Force -ErrorAction Stop
    $srcTime = $f.LastWriteTimeUtc
    $tgtTime = $tgtItem.LastWriteTimeUtc

    $stats.Conflicts++

    Ensure-Dir $BackupDir
    $backupPath = Join-Path $BackupDir $rel
    Ensure-Dir (Split-Path -Parent $backupPath)
    $finalBackup = Unique-Backup-Path $backupPath

    if ($srcTime -gt $tgtTime) {
      Move-Item -LiteralPath $tgt -Destination $finalBackup -Force -ErrorAction Stop
      Move-Item -LiteralPath $f.FullName -Destination $tgt -Force -ErrorAction Stop
      $stats.BackedUp++
    } else {
      Move-Item -LiteralPath $f.FullName -Destination $finalBackup -Force -ErrorAction Stop
      $stats.BackedUp++
      $stats.KeptDst++
    }
  }

  try {
    Get-ChildItem -LiteralPath $SourceDir -Recurse -Directory -Force -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending |
      ForEach-Object {
        if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
          Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        }
      }
    if (-not (Get-ChildItem -LiteralPath $SourceDir -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
      Remove-Item -LiteralPath $SourceDir -Force -ErrorAction SilentlyContinue
    }
  } catch {}

  return $stats
}

function Backup-Remaining-UserData-Root {
  param(
    [Parameter(Mandatory=$true)][string]$SrcRoot,
    [Parameter(Mandatory=$true)][string]$Stamp
  )

  if (-not (Test-Path -LiteralPath $SrcRoot)) { return $null }

  $remaining = Get-ChildItem -LiteralPath $SrcRoot -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin @("mods","earlyplugins") } |
    Select-Object -First 1

  if (-not $remaining) { return $null }

  $backupRoot = Join-Path (Split-Path -Parent $SrcRoot) ("UserData.root.backup." + $Stamp)
  Ensure-Dir $backupRoot

  Warn "Unexpected extra content found in AppData\UserData."
  Warn "Backing it up to: $backupRoot"

  foreach ($item in Get-ChildItem -LiteralPath $SrcRoot -Force -ErrorAction Stop) {
    if ($item.Name -in @("mods","earlyplugins")) { continue }
    Move-Item -LiteralPath $item.FullName -Destination $backupRoot -Force -ErrorAction Stop
  }

  return $backupRoot
}

try {
  if (-not (Is-Admin)) {
    Info "Admin rights required. Requesting UAC elevation..."
    if (-not $Elevated) {
      $argsList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`"",
        "-Elevated"
      )
      Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argsList | Out-Null
      Info "UAC request sent. You can close this window."
      Pause-And-Exit 0
    }
    Err "Elevation was refused or failed. Please run as Administrator."
    Pause-And-Exit 10
  }

  Ok "Running as Administrator."

  $regPath = "HKCU:\Software\Hypixel Studios\Hytale"
  $regName = "GameInstallPath"

  Info "Reading Hytale install path from registry..."
  $hytaleDir = (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction Stop).$regName
  if ([string]::IsNullOrWhiteSpace($hytaleDir)) { throw "Registry value '$regName' is empty." }
  Ok "Install path: $hytaleDir"

  $srcRoot = Join-Path $env:APPDATA "UserData"
  $dstRoot = Join-Path $hytaleDir "UserData"

  Info "AppData folder: $srcRoot"
  Info "Game folder  : $dstRoot"

  if (-not (Test-Path -LiteralPath $dstRoot)) {
    Err "Game UserData folder does not exist: $dstRoot"
    Pause-And-Exit 2
  }

  if (Is-LinkDir $srcRoot) {
    Ok "AppData\UserData is already a link. Nothing to do."
    Pause-And-Exit 0
  }

  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"

  $modsStats = Merge-Folder-Keep-Newest `
    -SourceDir (Join-Path $srcRoot "mods") `
    -TargetDir (Join-Path $dstRoot "mods") `
    -BackupDir (Join-Path $dstRoot ("mods.backup\" + $stamp)) `
    -Label "mods"

  $epStats = Merge-Folder-Keep-Newest `
    -SourceDir (Join-Path $srcRoot "earlyplugins") `
    -TargetDir (Join-Path $dstRoot "earlyplugins") `
    -BackupDir (Join-Path $dstRoot ("earlyplugins.backup\" + $stamp)) `
    -Label "earlyplugins"

  $rootBackup = Backup-Remaining-UserData-Root -SrcRoot $srcRoot -Stamp $stamp
  if ($rootBackup) { Ok "Extra content backed up." }

  if (Test-Path -LiteralPath $srcRoot) {
    Info "Removing AppData\UserData (required before creating the link)..."
    try {
      Remove-Item -LiteralPath $srcRoot -Force -Recurse -ErrorAction Stop
      Ok "AppData\UserData removed."
    } catch {
      Err "Could not remove AppData\UserData. Close Hytale/CurseForge and try again."
      Err $_.Exception.Message
      Pause-And-Exit 3
    }
  }

  Info "Creating symlink: AppData\UserData -> Game\UserData"
  New-Item -ItemType SymbolicLink -Path $srcRoot -Target $dstRoot -ErrorAction Stop | Out-Null
  Ok "Symlink created."

  Log ""
  Log "Summary:"
  Log ("- mods        : moved={0}, conflicts={1}, backed_up={2}, kept_destination={3}" -f $modsStats.Moved, $modsStats.Conflicts, $modsStats.BackedUp, $modsStats.KeptDst)
  Log ("- earlyplugins: moved={0}, conflicts={1}, backed_up={2}, kept_destination={3}" -f $epStats.Moved, $epStats.Conflicts, $epStats.BackedUp, $epStats.KeptDst)
  if ($rootBackup) { Log ("- extra AppData content backed up to: {0}" -f $rootBackup) }

  Ok "Done."
  Pause-And-Exit 0
}
catch {
  Err $_.Exception.Message
  Pause-And-Exit 99
}
