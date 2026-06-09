Write-Host "[test] Iniciando..."
$adb = Get-Command adb -ErrorAction SilentlyContinue
if ($adb) {
    Write-Host "[test] adb encontrado: $($adb.Source)"
} else {
    Write-Host "[test] adb nao encontrado no PATH"
}
Write-Host "[test] Fim"
