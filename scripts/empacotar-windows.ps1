# Arquivo SO com caracteres ASCII, de proposito: o Windows PowerShell 5.1 le
# .ps1 sem BOM como ANSI, e um travessao UTF-8 virava aspas e quebrava a string.
# Gera o instalador do NN Cloud para Windows. Rodar NUM PC COM WINDOWS, com:
#   - Flutter 3.41.6 (o mesmo do macOS) no PATH
#   - Visual Studio 2022 com "Desenvolvimento para desktop com C++" (inclui ATL)
#   - Inno Setup 6 (iscc.exe)
#
#   powershell -ExecutionPolicy Bypass -File scripts\empacotar-windows.ps1
#   (opcional) $env:CERTIFICADO_PFX / $env:SENHA_PFX para assinar com Authenticode
#
# ATENCAO: sem assinatura Authenticode o Windows mostra o aviso do SmartScreen na
# primeira vez ("Executar assim mesmo"). Funciona, mas assustar quem instala
# custa chamados: vale comprar um certificado de assinatura de codigo.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$versao = ((Select-String -Path pubspec.yaml -Pattern '^version:').Line -replace 'version:\s*', '' -replace '\+.*', '').Trim()
Write-Host "NN Cloud $versao"

flutter build windows --release
$saida = 'build\windows\x64\runner\Release'
if (-not (Test-Path "$saida\nncloud.exe")) { throw 'O build nao gerou o nncloud.exe.' }

# Runtime do Visual C++ ao lado do .exe (instalacao por usuario nao pode rodar o VC_redist).
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -property installationPath
$redist = Get-ChildItem "$vs\VC\Redist\MSVC" -Directory | Sort-Object Name -Descending | Select-Object -First 1
$crt = Get-ChildItem "$($redist.FullName)\x64" -Directory -Filter 'Microsoft.VC*.CRT' | Select-Object -First 1
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  Copy-Item (Join-Path $crt.FullName $dll) $saida -Force
}

function Assinar($arquivo) {
  if ($env:CERTIFICADO_PFX) {
    signtool sign /f $env:CERTIFICADO_PFX /p $env:SENHA_PFX /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $arquivo
  }
}
Assinar "$saida\nncloud.exe"

$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
& $iscc "/DVersao=$versao" 'instalador\windows\nncloud.iss'
$instalador = "build\instaladores\NN-Cloud-$versao-Windows.exe"
Assinar $instalador

(Get-FileHash $instalador -Algorithm SHA256).Hash.ToLower() + "  $instalador"
Write-Host "Pronto: $instalador - publique em Sistema > NN Cloud > Aplicativo (Windows)."
