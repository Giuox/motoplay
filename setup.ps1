# MotoPlay Setup per Windows VPS
# Esegui come Amministratore:
# powershell -ExecutionPolicy Bypass -File setup.ps1

# ── Check Amministratore ──────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) {
    Write-Host "[ERRORE] Esegui come Amministratore" -ForegroundColor Red
    Write-Host "Tasto destro su PowerShell -> Esegui come amministratore"
    Read-Host "Premi Invio per uscire"; exit 1
}

$ErrorActionPreference = "Continue"
$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Dir

function OK   { param($m) Write-Host "  [OK] $m" -ForegroundColor Green  }
function INFO { param($m) Write-Host "  [..] $m" -ForegroundColor Cyan   }
function WARN { param($m) Write-Host "  [!!] $m" -ForegroundColor Yellow }
function ERR  { param($m) Write-Host "  [XX] $m" -ForegroundColor Red; Read-Host "Premi Invio"; exit 1 }

Clear-Host
Write-Host ""
Write-Host "  ===========================================" -ForegroundColor Red
Write-Host "   MOTOPLAY - Setup Windows VPS" -ForegroundColor Red
Write-Host "  ===========================================" -ForegroundColor Red
Write-Host ""

# ── Raccolta configurazione ───────────────────────────────────
Write-Host "  --- Configurazione ---" -ForegroundColor Magenta
Write-Host ""
$Domain      = Read-Host "  Dominio (es. motoplay.miosito.com) [vuoto = HTTP senza dominio]"
$AuthPass    = Read-Host "  Password di accesso"
$MapboxToken = Read-Host "  Mapbox Token"
$SpotifyId   = Read-Host "  Spotify Client ID"

$UseHTTPS    = ($Domain -ne "")
$RedirectUri = if ($UseHTTPS) { "https://$Domain/callback.html" } else { "http://localhost:8000/callback.html" }

Write-Host ""
Write-Host "  Dominio   : $(if($UseHTTPS){$Domain}else{'nessuno (HTTP)'})"
Write-Host "  Directory : $Dir"
Write-Host "  Redirect  : $RedirectUri"
Write-Host ""
$ok = Read-Host "  Tutto corretto? (S/n)"
if ($ok -eq "n" -or $ok -eq "N") { exit 0 }

# ── Python ────────────────────────────────────────────────────
Write-Host ""
Write-Host "  --- Python ---" -ForegroundColor Magenta
$pyCmd = $null
foreach ($c in @("python","python3","py")) {
    try {
        $v = & $c --version 2>&1
        if ("$v" -match "Python 3") { $pyCmd = $c; break }
    } catch { }
}
if (-not $pyCmd) {
    INFO "Installo Python..."
    winget install --id Python.Python.3.12 --silent --accept-source-agreements --accept-package-agreements
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH","User")
    $pyCmd = "python"
}
OK "Python: $(& $pyCmd --version 2>&1)"

INFO "Installo dipendenze Python..."
& $pyCmd -m pip install -r "$Dir\requirements.txt" --quiet
OK "Dipendenze OK"

INFO "Genero icone PWA..."
& $pyCmd "$Dir\create_icons.py"
OK "Icone generate"

# ── Scarica Caddy ─────────────────────────────────────────────
Write-Host ""
Write-Host "  --- Caddy ---" -ForegroundColor Magenta
$CaddyExe = "$Dir\caddy.exe"
if (-not (Test-Path $CaddyExe)) {
    INFO "Scarico Caddy..."
    try {
        $rel    = Invoke-RestMethod "https://api.github.com/repos/caddyserver/caddy/releases/latest"
        $asset  = $rel.assets | Where-Object { $_.name -like "*windows_amd64.zip" } | Select-Object -First 1
        $tmpZip = "$env:TEMP\caddy_dl.zip"
        $tmpDir = "$env:TEMP\caddy_ex"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpZip
        Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
        Copy-Item "$tmpDir\caddy.exe" $CaddyExe
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
    } catch {
        ERR "Impossibile scaricare Caddy: $_"
    }
}
$caddyVer = (& $CaddyExe version 2>&1 | Select-Object -First 1)
OK "Caddy: $caddyVer"

# ── Scarica WinSW (alternativa a NSSM, sempre su GitHub) ─────
Write-Host ""
Write-Host "  --- WinSW (gestore servizi) ---" -ForegroundColor Magenta
$WinSW = "$Dir\winsw.exe"
if (-not (Test-Path $WinSW)) {
    INFO "Scarico WinSW da GitHub..."
    try {
        # Prova prima la release stabile v2.12.0
        $urls = @(
            "https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe",
            "https://github.com/winsw/winsw/releases/latest/download/WinSW-x64.exe"
        )
        $downloaded = $false
        foreach ($url in $urls) {
            try {
                Invoke-WebRequest -Uri $url -OutFile $WinSW -ErrorAction Stop
                $downloaded = $true; break
            } catch { }
        }
        if (-not $downloaded) { ERR "Impossibile scaricare WinSW. Controlla la connessione." }
    } catch {
        ERR "Errore WinSW: $_"
    }
}
OK "WinSW pronto"

# ── Crea config.js ────────────────────────────────────────────
Write-Host ""
Write-Host "  --- Configurazione app ---" -ForegroundColor Magenta

$configLines = @(
    "window.MOTOPLAY = {",
    "  MAPBOX_TOKEN:      '$MapboxToken',",
    "  SPOTIFY_CLIENT_ID: '$SpotifyId',",
    "  REDIRECT_URI:      '$RedirectUri',",
    "  SPOTIFY_SCOPES: [",
    "    'streaming','user-read-email','user-read-private',",
    "    'user-read-playback-state','user-modify-playback-state',",
    "    'user-read-currently-playing',",
    "  ].join(' '),",
    "};"
)
$configLines | Set-Content "$Dir\config.js" -Encoding UTF8
OK "config.js creato"

# ── Hash password Caddy ───────────────────────────────────────
INFO "Hash password..."
$hashRaw  = & $CaddyExe hash-password --plaintext $AuthPass 2>&1
$passHash = ($hashRaw | Where-Object { "$_" -match "^\`$2" } | Select-Object -First 1)
if (-not $passHash) {
    # Fallback: prende l'ultima riga non vuota
    $passHash = ($hashRaw | Where-Object { "$_".Trim() -ne "" } | Select-Object -Last 1)
}
$passHash = "$passHash".Trim()
OK "Password hashata"

# ── Crea Caddyfile ────────────────────────────────────────────
$logDir = "$Dir\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

if ($UseHTTPS) {
    $caddyLines = @(
        "{",
        "    email admin@$Domain",
        "}",
        "",
        "${Domain} {",
        "    basicauth {",
        "        motoplay $passHash",
        "    }",
        "    reverse_proxy localhost:8000",
        "}"
    )
    INFO "Configurazione HTTPS per $Domain"
} else {
    $caddyLines = @(
        ":80 {",
        "    basicauth {",
        "        motoplay $passHash",
        "    }",
        "    reverse_proxy localhost:8000",
        "}"
    )
    WARN "Nessun dominio: HTTP su porta 80 (PWA e Spotify richiedono HTTPS)"
}
$caddyLines | Set-Content "$Dir\Caddyfile" -Encoding UTF8
OK "Caddyfile creato"

# ── Registra servizi Windows ──────────────────────────────────
Write-Host ""
Write-Host "  --- Servizi Windows ---" -ForegroundColor Magenta

# Trova il vero eseguibile Python (non launcher/wrapper)
$pyFull = $null
$candidates = @(
    (Get-Command $pyCmd -ErrorAction SilentlyContinue).Source,
    "C:\Program Files\Python314\python.exe",
    "C:\Program Files\Python313\python.exe",
    "C:\Program Files\Python312\python.exe",
    "C:\Program Files\Python311\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python314\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
    "$env:APPDATA\Python\Python314\python.exe"
)
foreach ($p in $candidates) {
    if ($p -and (Test-Path $p) -and $p -notlike "*PyManager*") {
        # Verifica che sia un vero Python (non launcher)
        $test = & $p --version 2>&1
        if ("$test" -match "Python 3") { $pyFull = $p; break }
    }
}
# Se ancora non trovato, usa quello trovato prima (anche se PyManager)
if (-not $pyFull) {
    $pyFull = (Get-Command $pyCmd -ErrorAction SilentlyContinue).Source
}
if (-not $pyFull) { ERR "Python non trovato. Riavvia PowerShell dopo l'installazione." }
OK "Python path: $pyFull"

# Helper WinSW: crea XML + registra servizio
function WinSWSetup {
    param(
        [string]$Id,
        [string]$Description,
        [string]$Exe,
        [string]$Args,
        [string]$WorkDir,
        [hashtable]$EnvVars = @{}
    )

    # Crea XML config (no here-string per evitare problemi PS)
    $xml = @()
    $xml += "<?xml version=""1.0"" encoding=""UTF-8""?>"
    $xml += "<service>"
    $xml += "  <id>$Id</id>"
    $xml += "  <name>$Id</name>"
    $xml += "  <description>$Description</description>"
    $xml += "  <executable>$Exe</executable>"
    $xml += "  <arguments>$Args</arguments>"
    $xml += "  <workingdirectory>$WorkDir</workingdirectory>"
    foreach ($k in $EnvVars.Keys) {
        $xml += "  <env name=""$k"" value=""$($EnvVars[$k])""/>"
    }
    $xml += "  <logpath>$logDir</logpath>"
    $xml += "  <log mode=""roll-by-size"">"
    $xml += "    <sizeThreshold>5120</sizeThreshold>"
    $xml += "    <keepFiles>3</keepFiles>"
    $xml += "  </log>"
    $xml += "  <onfailure action=""restart"" delay=""5 sec""/>"
    $xml += "</service>"
    $xml | Set-Content "$Dir\$Id.xml" -Encoding UTF8

    # Copia WinSW exe con il nome del servizio (convenzione WinSW)
    $svcExe = "$Dir\$Id.exe"
    Copy-Item $WinSW $svcExe -Force

    # Disinstalla se esiste, poi installa
    & $svcExe uninstall 2>$null | Out-Null
    Start-Sleep -Milliseconds 300
    & $svcExe install | Out-Null
}

# Servizio MotoPlay
INFO "Registro servizio MotoPlay..."
WinSWSetup -Id "MotoPlay" `
    -Description "MotoPlay Connected Ride System" `
    -Exe $pyFull `
    -Args "server.py" `
    -WorkDir $Dir `
    -EnvVars @{ PORT = "8000" }
OK "Servizio MotoPlay registrato"

# Servizio Caddy
INFO "Registro servizio Caddy..."
WinSWSetup -Id "MotoPlayCaddy" `
    -Description "MotoPlay Caddy HTTPS Proxy" `
    -Exe $CaddyExe `
    -Args "run --config Caddyfile" `
    -WorkDir $Dir
OK "Servizio Caddy registrato"

# ── Firewall ──────────────────────────────────────────────────
Write-Host ""
Write-Host "  --- Firewall ---" -ForegroundColor Magenta
netsh advfirewall firewall delete rule name="MotoPlay HTTP"  2>$null | Out-Null
netsh advfirewall firewall delete rule name="MotoPlay HTTPS" 2>$null | Out-Null
netsh advfirewall firewall add rule name="MotoPlay HTTP"  dir=in action=allow protocol=TCP localport=80  | Out-Null
netsh advfirewall firewall add rule name="MotoPlay HTTPS" dir=in action=allow protocol=TCP localport=443 | Out-Null
OK "Porte 80 e 443 aperte"

# ── Avvia servizi ─────────────────────────────────────────────
Write-Host ""
Write-Host "  --- Avvio ---" -ForegroundColor Magenta
INFO "Avvio MotoPlay..."
& "$Dir\MotoPlay.exe" start 2>$null | Out-Null
Start-Sleep -Seconds 2

INFO "Avvio Caddy..."
& "$Dir\MotoPlayCaddy.exe" start 2>$null | Out-Null
Start-Sleep -Seconds 3

$mpStatus = (Get-Service -Name "MotoPlay"      -ErrorAction SilentlyContinue).Status
$cdStatus = (Get-Service -Name "MotoPlayCaddy" -ErrorAction SilentlyContinue).Status
if ($mpStatus -eq "Running") { OK "MotoPlay: Running" } else { WARN "MotoPlay: $mpStatus - controlla $logDir\MotoPlay.err.log" }
if ($cdStatus -eq "Running") { OK "Caddy: Running"    } else { WARN "Caddy: $cdStatus - controlla $logDir\MotoPlayCaddy.err.log" }

# ── Riepilogo finale ──────────────────────────────────────────
$finalUrl = if ($UseHTTPS) { "https://$Domain" } else { "http://$(hostname)" }
Write-Host ""
Write-Host "  =============================================" -ForegroundColor Green
Write-Host "   Setup completato!" -ForegroundColor Green
Write-Host "  =============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  URL      : $finalUrl" -ForegroundColor White
Write-Host "  Utente   : motoplay" -ForegroundColor White
Write-Host "  Password : (quella inserita)" -ForegroundColor White
Write-Host ""
if ($UseHTTPS) {
    Write-Host "  IMPORTANTE: punta il DNS di $Domain" -ForegroundColor Yellow
    Write-Host "  all'IP di questa VPS per attivare HTTPS." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Spotify Redirect URI da aggiungere:" -ForegroundColor Yellow
    Write-Host "  $RedirectUri" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "  Comandi utili:" -ForegroundColor Cyan
Write-Host "    & '$Dir\MotoPlay.exe' restart"
Write-Host "    & '$Dir\MotoPlayCaddy.exe' restart"
Write-Host "    Get-Content '$logDir\server.log' -Wait"
Write-Host "    Get-Content '$logDir\caddy.log' -Wait"
Write-Host ""
Read-Host "  Premi Invio per chiudere"
