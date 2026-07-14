# scripts/diag-ws-403.ps1
# Diagnostic for: WS upgrade returns 403 while REST sync works.
#
# Injects a tagged debug print in sync_service.dart (already added),
# captures the access token from logcat when you open a note,
# then runs 3 curls to disambiguate the hypothesis tree:
#   A) GET /api/v1/notes/{id}        -> note visible to this user?
#   B) WS handshake /sync/ws/{id}     -> 403 access denied? (red-capable)
#   C) GET /api/v1/auth/me            -> what is the JWT sub?
#
# Usage:
#   1. Edit lib/core/sync/sync_service.dart:142 to print the tag
#      (already done — line `[DEBUG-DIAG] note_id=... access_token=...`)
#   2. Restart the app on the device
#   3. Run: ./scripts/diag-ws-403.ps1
#   4. Open a note in the app when prompted
#   5. Cleanup: remove the debugPrint line marked [DEBUG-DIAG]
#
# All requests go to the same host the app uses:
#   https://backend-winter-waterfall-5807.fly.dev

[CmdletBinding()]
param(
    [string]$NoteId = '004e4424-6200-4f36-a068-923cc242e249',
    [string]$BaseUrl = 'https://backend-winter-waterfall-5807.fly.dev',
    [int]$CaptureTimeoutSec = 60
)

$ErrorActionPreference = 'Stop'

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    $adb = (Get-Command adb -ErrorAction SilentlyContinue)?.Source
    if (-not $adb) { throw 'adb not found. Install Android platform-tools.' }
}

$devices = & $adb devices
if ($devices -notmatch '\semulator|device\t') {
    throw 'No Android device/emulator connected. Start one and reconnect.'
}
Write-Host "Using adb: $adb"

# --- Step 1: tail logcat for [DEBUG-DIAG] ---------------------------

Write-Host ''
Write-Host '== Step 1: capture access token from logcat ==' -ForegroundColor Cyan
Write-Host 'Clearing logcat buffer...'
& $adb logcat -c | Out-Null

Write-Host "Now OPEN A NOTE that has the 403 problem in the app."
Write-Host "Will wait up to $CaptureTimeoutSec seconds for the [DEBUG-DIAG] line..."

$token = $null
$noteIdFromLog = $null
$deadline = (Get-Date).AddSeconds($CaptureTimeoutSec)

# Poll logcat in chunks until we see the tag, or timeout.
while ((Get-Date) -lt $deadline) {
    $line = & $adb logcat -d -s flutter 2>$null |
        Select-String '\[DEBUG-DIAG\] note_id=([0-9a-f-]+) access_token=(.+)' |
        Select-Object -Last 1
    if ($line) {
        $noteIdFromLog = $line.Matches[0].Groups[1].Value
        $token = $line.Matches[0].Groups[2].Value.Trim()
        break
    }
    Start-Sleep -Milliseconds 500
}

if (-not $token) {
    Write-Host 'Did not capture [DEBUG-DIAG] line. Ensure:' -ForegroundColor Red
    Write-Host '  - you edited sync_service.dart and hot-restarted the app'
    Write-Host '  - you actually opened a note (connectNote runs the debugPrint)'
    Write-Host '  - the device is the one adb is pointing at'
    exit 1
}

Write-Host "Captured." -ForegroundColor Green
Write-Host "  noteId from log : $noteIdFromLog"
Write-Host "  access_token len: $($token.Length)"
Write-Host "  access_token[:12]: $($token.Substring(0,[Math]::Min(12,$token.Length)))..."
Write-Host ''

# Prefer the noteId from the log if it differs from the default.
$targetNoteId = if ($noteIdFromLog) { $noteIdFromLog } else { $NoteId }

# --- Step 2: run the three curls ------------------------------------

function Invoke-Curl {
    param(
        [string]$Label,
        [string[]]$Args
    )
    Write-Host "==> $Label" -ForegroundColor Cyan
    $out = & curl @Args -sS -i -N 2>&1
    $statusLine = ($out | Select-String -Pattern '^HTTP/[\d.]+ \d{3}').Line
    $bodyLine = ($out | Select-String -Pattern '^\{.*\}').Line
    Write-Host "  $($statusLine -replace "`r","")"
    if ($bodyLine) { Write-Host "  body: $($bodyLine -replace "`r","")" }
    Write-Host ''
    return [pscustomobject]@{ Label = $Label; Status = $statusLine; Body = $bodyLine }
}

$authHdr = "Authorization: Bearer $token"

$results = @()

# A) Does this user own (or see) the note via REST?
$A = Invoke-Curl 'A) REST: GET /api/v1/notes/{noteId}' @(
    '-H', $authHdr,
    "$BaseUrl/api/v1/notes/$targetNoteId"
)
$results += $A

# B) WS handshake with the same token. Should reproduce the 403.
$B = Invoke-Curl 'B) WS handshake with auth (should reproduce 403)' @(
    '-H', 'Connection: Upgrade',
    '-H', 'Upgrade: websocket',
    '-H', 'Sec-WebSocket-Version: 13',
    '-H', 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==',
    '-H', $authHdr,
    "$BaseUrl/api/v1/sync/ws/$targetNoteId"
)
$results += $B

# C) Who does the JWT think the user is?
# Try common endpoints; whoever responds 200 is the real one.
$triedAuthMe = $false
foreach ($path in '/api/v1/auth/me', '/api/v1/me', '/api/v1/users/me') {
    $C = Invoke-Curl "C) JWT subject: GET $path" @(
        '-H', $authHdr,
        "$BaseUrl$path"
    )
    if ($C.Status -match ' 200 ') { $triedAuthMe = $true; break }
    $results += $C
}
if (-not $triedAuthMe) {
    Write-Host '(no /me endpoint responded 200 — list more if needed)' -ForegroundColor Yellow
    Write-Host ''
}

# --- Step 3: summary -----------------------------------------------

Write-Host '== Summary ==' -ForegroundColor Cyan
$results | Format-Table Label, Status, Body -AutoSize

Write-Host ''
Write-Host '== Hypothesis decision tree ==' -ForegroundColor Cyan
Write-Host 'Use these rules to interpret:'
Write-Host '  A 404/403 + B 403 access denied     => H1: user does not own the note; row is stale local'
Write-Host '  A 200      + B 403 access denied     => H2: JWT sub != notes.user_id (parse/mismatch bug)'
Write-Host '  A 200      + B 200 (handshake ok)    => mismatch elsewhere; re-run with longer capture window'

Write-Host ''
Write-Host '== Cleanup reminder ==' -ForegroundColor Yellow
Write-Host 'After done, revert the temporary debug print in'
Write-Host '  lib/core/sync/sync_service.dart (line with [DEBUG-DIAG])'
Write-Host 'grep -n "[DEBUG-DIAG]" lib/core/sync/sync_service.dart'