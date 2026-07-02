# Windows setup script (winget + npm)
# Run (admin NOT required - installs are user-scope; only retry as Administrator
# if a system-wide install fails with access denied):
#   powershell -ExecutionPolicy Bypass -File install.ps1
#   pwsh      -ExecutionPolicy Bypass -File install.ps1
#
# One-liner (safe even on a fresh PC with default Restricted policy):
#   irm https://raw.githubusercontent.com/hd0126/dev-setup/main/install.ps1 | iex

# 파일 실행이면 경로, irm | iex면 빈 값. irm | iex에서 `exit`는 사용자의
# 터미널 세션을 통째로 닫아버리므로, 중단할 때 이 값으로 exit/return을 고른다.
$RunAsFile = [bool]$PSCommandPath

# ── Allow scripts in THIS process so npm.ps1 and the profile can load ──
# Default Windows policy is Restricted, which blocks npm (npm is npm.ps1).
# Process scope: no admin needed, nothing is changed system-wide.
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction Stop } catch {}

# Ensure TLS 1.2 for HTTPS downloads. Modern Win10/11 use SystemDefault (which
# already negotiates TLS 1.2), but older Windows PowerShell 5.1 hosts default to
# TLS 1.0 and would fail to reach GitHub/npm. -bor only adds, never removes.
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# ── Non-interactive / dry-run (unattended installs and CI) ──────────────────
# Set these env vars BEFORE running (works with the irm | iex one-liner too):
#   $env:DEVSETUP_NONINTERACTIVE=1  -> skip the selection menu, install the defaults
#   $env:DEVSETUP_DRYRUN=1          -> print the install plan but change nothing
# GitHub Actions sets CI=true, which is treated as non-interactive automatically.
$DryRun         = -not [string]::IsNullOrEmpty($env:DEVSETUP_DRYRUN)
$NonInteractive = $DryRun -or (-not [string]::IsNullOrEmpty($env:DEVSETUP_NONINTERACTIVE)) -or ($env:CI -eq 'true')

$packages = @(
    @{
        Id   = "OpenJS.NodeJS.LTS"
        Name = "Node.js LTS"
        Desc = "JS runtime. Required for codex, gemini-cli, omc, omx."
        Ex   = "node --version / npm install -g <pkg>"
        On   = $true
    },
    @{
        Id   = "Git.Git"
        Name = "Git"
        Desc = "Version control. Required for GitHub CLI and Claude Code."
        Ex   = "git clone / git commit / git push"
        On   = $true
    },
    @{
        Id       = "GitHub.cli"
        Name     = "GitHub CLI"
        Desc     = "Manage GitHub PRs, issues, gists from terminal."
        Ex       = "gh pr create / gh gist list"
        On       = $true
        Requires = @("Git")
    },
    @{
        Id   = "Microsoft.PowerShell"
        Name = "PowerShell 7"
        Desc = "pwsh 7. This profile requires pwsh 7."
        Ex   = "pwsh"
        On   = $true
    },
    @{
        Id   = "Starship.Starship"
        Name = "Starship"
        Desc = "Fast prompt. NOTE: this profile uses its own pure-PS prompt for speed; Starship is installed but idle until you enable it (see README)."
        Ex   = "'Invoke-Expression (&starship init powershell)' | Add-Content `$PROFILE"
        On   = $true
    },
    @{
        Id       = "DEVCOM.JetBrainsMonoNerdFont"
        Name     = "JetBrainsMono Nerd Font"
        Desc     = "Nerd Font for Starship icons. Prevents broken glyphs in the prompt."
        Ex       = "Set terminal font to 'JetBrainsMono Nerd Font' after install"
        On       = $true
        Optional = $true
    },
    @{
        Id   = "ajeetdsouza.zoxide"
        Name = "zoxide"
        Desc = "Smart cd based on history. No need to type full path."
        Ex   = "z proj  ->  C:\Users\me\Documents\projects"
        On   = $true
    },
    @{
        Id   = "junegunn.fzf"
        Name = "fzf"
        Desc = "Fuzzy finder UI. Ctrl+R history, Ctrl+T file search."
        Ex   = "Ctrl+R -> history / Ctrl+T -> file search"
        On   = $true
    },
    @{
        Id   = "BurntSushi.ripgrep.MSVC"
        Name = "ripgrep"
        Desc = "Faster grep. Auto applies .gitignore."
        Ex   = "rg 'function' src/"
        On   = $true
    },
    @{
        Id   = "Python.Python.3.12"
        Name = "Python 3.12"
        Desc = "General purpose language. Data, automation, AI."
        Ex   = "python --version / pip install <pkg>"
        On   = $true
    },
    @{
        Id   = "astral-sh.uv"
        Name = "uv"
        Desc = "Fast Python package and project manager (pip/venv replacement)."
        Ex   = "uv venv / uv pip install <pkg>"
        On   = $true
    }
)

$npmPackages = @(
    @{
        Name      = "Claude Code"
        Desc      = "Anthropic AI coding CLI. Native installer (Anthropic-recommended) - auto-updates in the background."
        Ex        = "cc / ccc (continue) / ccr (resume)"
        On        = $true
        Native    = $true
        Installer = "https://claude.ai/install.ps1"
    },
    @{
        Name      = "codex (OpenAI)"
        Desc      = "OpenAI Codex CLI. Native installer - no Node dependency, self-updating (OpenAI-recommended). Installed before omx so omx has its engine."
        Ex        = "codex 'write tests'"
        On        = $true
        Native    = $true
        Installer = "https://chatgpt.com/codex/install.ps1"
    },
    @{
        Name = "@google/gemini-cli"
        Desc = "Google Gemini CLI."
        Ex   = "gemini 'explain this code'"
        On   = $true
    },
    @{
        Name = "oh-my-codex"
        Desc = "Multi-agent orchestration for Codex (omx). Tuned for macOS/Linux; native Windows is less supported (WSL2 recommended)."
        Ex   = "omx"
        On   = $true
    }
    # Note: omc (oh-my-claudecode) is installed as a Claude Code PLUGIN below,
    # not via npm. The npm package pulls native modules (better-sqlite3) that
    # need a C++ toolchain on Windows; the plugin needs none and is the same version.
)

# ── Interactive menu (native PowerShell checkbox UI) ──────
function Show-Menu {
    param($items, $title, [bool]$canGoBack = $false)

    $cursor = 0
    $Host.UI.RawUI.CursorSize = 0

    while ($true) {
        Clear-Host
        $selectedCount = ($items | Where-Object { $_.On }).Count

        Write-Host "=== $title  ($selectedCount / $($items.Count) selected) ===" -ForegroundColor Yellow
        $nav = if ($canGoBack) { "  |  Left/Backspace: back" } else { "" }
        Write-Host "  Up/Down: move  |  Space: toggle  |  A: select all  |  Enter: confirm$nav  |  Esc: cancel" -ForegroundColor DarkGray
        Write-Host ""

        for ($i = 0; $i -lt $items.Count; $i++) {
            $mark  = if ($items[$i].On) { "[v]" } else { "[ ]" }
            $arrow = if ($i -eq $cursor) { ">" } else { " " }
            $color = if ($items[$i].On) { "Cyan" } else { "DarkGray" }
            Write-Host "  $arrow $mark $($items[$i].Name)  " -NoNewline -ForegroundColor $color
            Write-Host "$($items[$i].Desc)" -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host "  ex) $($items[$cursor].Ex)" -ForegroundColor DarkGray

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        switch ($key.VirtualKeyCode) {
            38 { if ($cursor -gt 0) { $cursor-- } }
            40 { if ($cursor -lt $items.Count - 1) { $cursor++ } }
            32 {
                $items[$cursor].On = -not $items[$cursor].On
                if ($items[$cursor].On -and $items[$cursor].Requires) {
                    foreach ($req in $items[$cursor].Requires) {
                        $dep = $items | Where-Object { $_.Name -eq $req }
                        if ($dep) { $dep.On = $true }
                    }
                }
            }
            65 {
                $allOn = ($items | Where-Object { -not $_.On }).Count -eq 0
                foreach ($item in $items) { $item.On = -not $allOn }
            }
            13 { $Host.UI.RawUI.CursorSize = 25; return $items }
            37 { if ($canGoBack) { $Host.UI.RawUI.CursorSize = 25; return "__BACK__" } }   # Left arrow -> previous page
            8  { if ($canGoBack) { $Host.UI.RawUI.CursorSize = 25; return "__BACK__" } }   # Backspace  -> previous page
            27 { $Host.UI.RawUI.CursorSize = 25; return "__CANCEL__" }   # Esc -> cancel (exit는 iex 세션을 닫으므로 금지)
        }
    }
}

# Two-step selection wizard. Left/Backspace on the npm page returns to the
# winget page; selections on each page are preserved (objects are mutated in
# place) so moving back and forth never loses what was already toggled.
if ($NonInteractive) {
    $mode = if ($DryRun) { "DRY-RUN" } else { "non-interactive" }
    Write-Host "[$mode] skipping menu - using the default selection (all items On)." -ForegroundColor Yellow
} else {
    Clear-Host
    $step = 0
    $cancelled = $false
    while ($step -lt 2) {
        if ($step -eq 0) {
            $res = Show-Menu -items $packages -title "Packages to install"
            if ($res -is [string] -and $res -eq "__CANCEL__") { $cancelled = $true; break }
            $packages = $res
            $step++
        } else {
            $res = Show-Menu -items $npmPackages -title "AI CLI tools" -canGoBack $true
            if ($res -is [string] -and $res -eq "__CANCEL__") { $cancelled = $true; break }
            if ($res -is [string] -and $res -eq "__BACK__") {
                $step--          # go back to the winget page
            } else {
                $npmPackages = $res
                $step++
            }
        }
    }
    if ($cancelled) {
        Write-Host "Cancelled." -ForegroundColor Red
        if ($RunAsFile) { exit 0 } else { return }
    }
}

# ── Auto-add Node.js if a Node-based CLI is selected (native installers don't need it) ──
# Use ContainsKey before reading .Native: packages without that key would throw a
# "property not found" error under Set-StrictMode, which a native installer (or a
# user profile) can switch on. This guard keeps the lookup safe in any session.
$needsNode = $npmPackages | Where-Object { $_.On -and -not ($_.ContainsKey('Native') -and $_.Native) }
if ($needsNode) {
    $nodePkg = $packages | Where-Object { $_.Name -eq "Node.js LTS" }
    if ($nodePkg -and -not $nodePkg.On) {
        $nodePkg.On = $true
        Write-Host "Node.js LTS auto-added (required for npm packages)" -ForegroundColor Yellow
    }
}

# ── Summary ───────────────────────────────────────────────
Write-Host ""
Write-Host "Items to install:" -ForegroundColor Green
$packages    | Where-Object { $_.On } | ForEach-Object { Write-Host "  [winget] $($_.Name)" -ForegroundColor Cyan }
$npmPackages | Where-Object { $_.On } | ForEach-Object {
    $tag = if ($_.ContainsKey('Native') -and $_.Native) { "[native]" } else { "[npm]   " }
    Write-Host "  $tag $($_.Name)" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "Starting installation..." -ForegroundColor Green

# ── Check winget ──────────────────────────────────────────
if (-not $DryRun -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "winget not found. Install 'App Installer' from Microsoft Store." -ForegroundColor Red
    if ($RunAsFile) { exit 1 } else { return }
}

# ── Install winget packages ───────────────────────────────
$wingetList  = @($packages | Where-Object { $_.On })
$wingetTotal  = $wingetList.Count
$wingetIdx    = 0
$failedPkgs   = @()
$optionalFails = @()

foreach ($pkg in $wingetList) {
    $wingetIdx++
    Write-Host "[$wingetIdx/$wingetTotal] $($pkg.Name)..." -ForegroundColor Cyan -NoNewline
    if ($DryRun) { Write-Host " [DRY-RUN] would install/upgrade ($($pkg.Id))" -ForegroundColor DarkGray; continue }

    # Check if already installed, and from which source
    $listOut = winget list --id $pkg.Id --exact --accept-source-agreements 2>&1 | Out-String
    $alreadyInstalled = ($LASTEXITCODE -eq 0)
    $isStoreManaged   = $alreadyInstalled -and ($listOut -match 'msstore|Microsoft Store')

    if ($isStoreManaged) {
        Write-Host " [SKIP] Microsoft Store version detected - uninstall it first to use winget version" -ForegroundColor Yellow
        $failedPkgs += "$($pkg.Name) (Store conflict)"
        continue
    }

    if ($alreadyInstalled) {
        winget upgrade $pkg.Id --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    } else {
        winget install $pkg.Id --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    }
    $exit = $LASTEXITCODE

    # Retry a failed fresh install with user scope. Machine-scope installs can
    # fail with access-denied (exit 5) or crash the installer with an access
    # violation (0xC0000005 / -1073741819) on locked-down PCs or when antivirus
    # blocks the elevated installer; user scope needs no elevation.
    if (-not $alreadyInstalled -and $exit -ne 0 -and $exit -ne -1978335189) {
        Write-Host " retry (user scope)..." -ForegroundColor DarkGray -NoNewline
        winget install $pkg.Id --scope user --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        $exit = $LASTEXITCODE
    }
    if ($exit -eq 0) {
        if ($alreadyInstalled) { Write-Host " [UPGRADED]"  -ForegroundColor Green }
        else                   { Write-Host " [INSTALLED]" -ForegroundColor Green }
    } elseif ($exit -eq -1978335189) {
        Write-Host " [OK - already latest]" -ForegroundColor Green   # 0x8A15002B (no update needed)
    } else {
        $reason = switch ($exit) {
            1603        { "installer conflict (exit 1603)" }
            -1073741819 { "installer crashed (0xC0000005 access violation - often antivirus or a broken VC++ runtime)" }
            5           { "access denied (exit 5 - try running this script once as Administrator)" }
            default     { "exit $exit" }
        }
        if ($pkg.Optional) {
            # Optional extras (e.g. fonts) must never fail the whole run.
            Write-Host " [SKIP] optional - $reason" -ForegroundColor Yellow
            $optionalFails += "$($pkg.Name) ($reason)"
        } else {
            Write-Host " [FAILED] $reason" -ForegroundColor Red
            $failedPkgs += "$($pkg.Name) ($reason)"
        }
    }
}

# Refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User") + ";" +
            "$env:APPDATA\npm"

# ── zoxide fallback: standalone binary if winget failed ───
# winget can crash (0xC0000005) or be denied (exit 5) on locked-down PCs and
# never recover. zoxide ships as a single static binary, so when it is still
# missing after winget, drop the prebuilt exe on PATH directly.
$zoxidePkg = $packages | Where-Object { $_.Id -eq 'ajeetdsouza.zoxide' }
if ($zoxidePkg -and $zoxidePkg.On -and -not $DryRun -and -not (Get-Command zoxide -ErrorAction SilentlyContinue)) {
    Write-Host "zoxide missing after winget - installing standalone binary..." -ForegroundColor Yellow
    try {
        $arch  = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
        $rel   = Invoke-RestMethod 'https://api.github.com/repos/ajeetdsouza/zoxide/releases/latest' -Headers @{ 'User-Agent' = 'omc-install' }
        $asset = $rel.assets | Where-Object { $_.name -like "*$arch-pc-windows-msvc*.zip" } | Select-Object -First 1
        if (-not $asset) { throw "no Windows binary for arch '$arch'" }
        $zip = Join-Path $env:TEMP 'zoxide.zip'
        $dir = Join-Path $env:TEMP 'zoxide-bin'
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $dir -Force
        $exe = Get-ChildItem -Path $dir -Recurse -Filter 'zoxide.exe' | Select-Object -First 1
        if (-not $exe) { throw "zoxide.exe not found in archive" }
        $binDir = Join-Path $env:LOCALAPPDATA 'Programs\zoxide'
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        Copy-Item $exe.FullName (Join-Path $binDir 'zoxide.exe') -Force
        # Persist on the user PATH (no admin needed) and add to the current session.
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($userPath -notlike "*$binDir*") {
            [Environment]::SetEnvironmentVariable('Path', "$userPath;$binDir", 'User')
        }
        $env:Path += ";$binDir"
        $failedPkgs = @($failedPkgs | Where-Object { $_ -notlike 'zoxide*' })
        Write-Host "  zoxide $($rel.tag_name) installed to $binDir and added to PATH." -ForegroundColor Green
    } catch {
        Write-Host "  zoxide fallback failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Install manually from https://github.com/ajeetdsouza/zoxide/releases" -ForegroundColor DarkGray
    }
}

# ── Install npm packages ──────────────────────────────────
# 요약부(line ~710)가 이 두 플래그를 읽으므로 npm 블록 진입 여부와 무관하게,
# 그리고 strict-mode 프로필에서도 안전하도록 여기서 초기화한다.
$npmNativeFail  = $false
$npmNetworkFail = $false
$selectedNpm = $npmPackages | Where-Object { $_.On }
if ($selectedNpm) {
    # npm is only needed for non-native CLIs (codex and Claude Code use native installers).
    $npmCmd = $null
    if (-not $DryRun -and ($selectedNpm | Where-Object { -not ($_.ContainsKey('Native') -and $_.Native) })) {
        # Use npm.cmd explicitly: PowerShell would otherwise resolve "npm" to
        # npm.ps1, which is blocked by execution policy on locked-down (GPO) PCs.
        # .cmd is not subject to execution policy at all.
        $npmCmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
        if (-not $npmCmd) {
            Write-Host ""
            Write-Host "npm not found. Restart PowerShell and run this script again." -ForegroundColor Red
            if ($RunAsFile) { exit 1 } else { return }
        }
    }
    $npmTotal = @($selectedNpm).Count
    $npmIdx   = 0
    Write-Host "Installing AI CLI tools..." -ForegroundColor Cyan
    foreach ($pkg in $selectedNpm) {
        $npmIdx++
        Write-Host "[$npmIdx/$npmTotal] $($pkg.Name)..." -ForegroundColor DarkGray -NoNewline
        $isNative = $pkg.ContainsKey('Native') -and $pkg.Native
        if ($DryRun) {
            $how = if ($isNative) { "native installer" } else { "npm -g" }
            Write-Host " [DRY-RUN] would install ($how)" -ForegroundColor DarkGray
            continue
        }

        # Native installer (Claude Code, Codex): standalone binary, no Node dependency.
        #
        # Run it in an ISOLATED child process (powershell.exe -NoProfile) instead of
        # `irm | iex` in this scope. That isolation fixes two real failures:
        #   1. Strict-mode leak (downstream): these installers call
        #      `Set-StrictMode -Version Latest`. With `irm | iex` that leaks into this
        #      script, so the next package's `$pkg.Native` lookup (on a hashtable that
        #      has no such key) throws "property not found" and aborts the whole run.
        #   2. Profile pollution (upstream): -NoProfile gives the installer a clean
        #      session, so a strict-mode (or otherwise quirky) user profile can't break
        #      the installer's own arch detection (e.g. RuntimeInformation::OSArchitecture).
        # The child runs with -ExecutionPolicy Bypass so the saved .ps1 runs under the
        # default Restricted policy too.
        if ($isNative) {
            # 이미 네이티브 설치돼 있으면 대용량 재다운로드 skip — 네이티브 빌드는
            # 백그라운드 자동 업데이트가 있어 기존 설치로 충분 (mac/linux와 동일 동작)
            $nativeExe = if ($pkg.Name -eq 'Claude Code') { 'claude.exe' } else { 'codex.exe' }
            $nativeBin = Join-Path $env:USERPROFILE ".local\bin\$nativeExe"
            if (Test-Path $nativeBin) {
                Write-Host " [OK - already installed (native, self-updating)]" -ForegroundColor Green
                continue
            }
            Write-Host ""
            $tmp = Join-Path $env:TEMP "devsetup-native-$npmIdx.ps1"
            try {
                Invoke-RestMethod $pkg.Installer -OutFile $tmp
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  -> $($pkg.Name) [OK - native installer]" -ForegroundColor Green
                    # Claude Code's Windows native installer drops claude.exe in
                    # %USERPROFILE%\.local\bin but, unlike codex, does NOT add that
                    # folder to PATH. Persist it (and add to this session) so the
                    # `claude` command resolves after install / in a new terminal.
                    if ($pkg.Name -eq 'Claude Code') {
                        $localBin = Join-Path $env:USERPROFILE '.local\bin'
                        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
                        if ($userPath -notlike "*$localBin*") {
                            [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $localBin), 'User')
                            Write-Host "     added $localBin to your PATH" -ForegroundColor DarkGray
                        }
                        if ($env:Path -notlike "*$localBin*") { $env:Path += ";$localBin" }
                    }
                } else {
                    Write-Host "  -> $($pkg.Name) [FAILED] native installer (exit $LASTEXITCODE)" -ForegroundColor Red
                    $failedPkgs += "$($pkg.Name) (native installer)"
                }
            } catch {
                Write-Host "  -> $($pkg.Name) [FAILED] native installer: $($_.Exception.Message)" -ForegroundColor Red
                $failedPkgs += "$($pkg.Name) (native installer)"
            } finally {
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            }
            continue
        }

        # Fast local check (no network): is it installed, and at what version?
        $installedVer = $null
        $lsJson = & $npmCmd.Source ls -g $pkg.Name --depth=0 --json 2>$null | Out-String
        if ($lsJson) { try { $installedVer = ($lsJson | ConvertFrom-Json).dependencies.($pkg.Name).version } catch {} }

        # If installed, one quick metadata call decides upgrade vs already-latest.
        # Skipping the reinstall when current is the big time saver - npm install -g
        # otherwise re-resolves and rebuilds native modules on every run.
        $latestVer = $null
        if ($installedVer) {
            $latestVer = (& $npmCmd.Source view $pkg.Name version 2>$null | Out-String).Trim()
            if ($latestVer -and ($latestVer -eq $installedVer)) {
                Write-Host " [OK - already latest ($installedVer)]" -ForegroundColor Green
                continue
            }
        }

        $npmLog = & $npmCmd.Source install -g $pkg.Name 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            # Retry once: covers transient network drops and prebuilt-binary
            # downloads that occasionally fail on the first attempt.
            Write-Host " retry..." -ForegroundColor DarkGray -NoNewline
            $npmLog = & $npmCmd.Source install -g $pkg.Name 2>&1 | Out-String
        }
        if ($LASTEXITCODE -eq 0) {
            if ($installedVer) { Write-Host " [UPGRADED $installedVer -> $latestVer]" -ForegroundColor Green }
            else               { Write-Host " [INSTALLED]" -ForegroundColor Green }
        } else {
            Write-Host " [FAILED] exit $LASTEXITCODE" -ForegroundColor Red
            $failedPkgs += "$($pkg.Name) (npm exit $LASTEXITCODE)"

            # Save the full log and surface the key error lines so the real
            # root cause (build tools vs blocked download) is visible.
            $safeName = ($pkg.Name -replace '[^\w.-]', '_')
            $logFile  = Join-Path $env:TEMP "omc-install-$safeName.log"
            $npmLog | Out-File -FilePath $logFile -Encoding utf8
            $keyLines = $npmLog -split "`r?`n" |
                Where-Object { $_ -match 'npm ERR!|gyp ERR!|prebuild|ETIMEDOUT|ECONNRESET|ENOTFOUND|EACCES|403|proxy|MSBuild|Visual Studio|node-gyp|fatal error|cannot find|self.signed' } |
                Select-Object -Last 12
            if ($keyLines) {
                Write-Host "    --- error detail ---" -ForegroundColor DarkGray
                foreach ($l in $keyLines) { Write-Host "    $($l.Trim())" -ForegroundColor DarkGray }
            }
            Write-Host "    full log saved to: $logFile" -ForegroundColor DarkGray

            # Detect native-module build failures (better-sqlite3, node-gyp, etc.)
            if ($npmLog -match 'node-gyp|gyp ERR|MSBuild|prebuild|better.sqlite3|Visual Studio|node_gyp|C\+\+') {
                $npmNativeFail = $true
            }
            # Detect network/proxy failures (corporate firewall blocking downloads)
            if ($npmLog -match 'ETIMEDOUT|ECONNRESET|ENOTFOUND|ECONNREFUSED|403 Forbidden|self.signed certificate|tunneling socket') {
                $npmNetworkFail = $true
            }
        }
    }
}

# ── oh-my-codex (omx) Windows caveat ──────────────────────
# Per its README, omx is primarily tuned for macOS/Linux; native Windows is a
# best-effort path that may behave inconsistently. Surface that so Windows users
# (this installer is Windows-only) know WSL2 is the more reliable path for omx.
$omxSelected = $npmPackages | Where-Object { $_.On -and $_.Name -eq 'oh-my-codex' }
if ($omxSelected) {
    Write-Host ""
    Write-Host "Note: oh-my-codex (omx) is primarily tuned for macOS/Linux." -ForegroundColor Yellow
    Write-Host "  On native Windows it may behave inconsistently (per its README)." -ForegroundColor DarkGray
    Write-Host "  For the most reliable experience, run omx inside WSL2." -ForegroundColor DarkGray
}

# Allow profile to run
# Run in a child process to avoid the -ExecutionPolicy Bypass override from the parent shell
if (-not $DryRun) {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        pwsh -Command "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" 2>$null
    } else {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue
    }
}

# Download PowerShell profile from the repo
if (-not $DryRun) {
    Write-Host "Downloading PowerShell profile..." -ForegroundColor Cyan
    $gistUrl = "https://raw.githubusercontent.com/hd0126/dev-setup/main/Microsoft.PowerShell_profile.ps1"
    $pwshProfilePath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "PowerShell\Microsoft.PowerShell_profile.ps1"
    $profileDir = Split-Path $pwshProfilePath
    New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
    if (Test-Path $pwshProfilePath) {
        $bakPath = "$pwshProfilePath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $pwshProfilePath $bakPath
        Write-Host "  Existing profile backed up: $bakPath" -ForegroundColor DarkGray
    }
    Invoke-WebRequest -Uri $gistUrl -OutFile $pwshProfilePath -UseBasicParsing

    # 방금 설치된 도구(zoxide/fzf/starship)가 프로필의 도구 캐시에 반영되도록
    # 캐시를 무효화한다 — 안 하면 이전 캐시(도구 없음)가 남아 zoxide/fzf가
    # 새 터미널에서도 계속 비활성 상태로 보인다.
    Remove-Item "$env:TEMP\pwsh_tools_cache.ps1", "$env:TEMP\zoxide_init_cache.ps1" -Force -ErrorAction SilentlyContinue
    Write-Host "  Tool cache invalidated (fresh detection on next shell)." -ForegroundColor DarkGray
} else {
    Write-Host "[DRY-RUN] would download the PowerShell profile to `$PROFILE." -ForegroundColor DarkGray
}

# ── Nerd Font: guarantee install + apply to terminals ─────
$fontPkg = $packages | Where-Object { $_.Id -eq 'DEVCOM.JetBrainsMonoNerdFont' }
if ($fontPkg -and $fontPkg.On -and -not $DryRun) {
    Write-Host ""
    Write-Host "Configuring Nerd Font..." -ForegroundColor Cyan
    $face     = "JetBrainsMono Nerd Font"
    $faceMono = "JetBrainsMono Nerd Font Mono"
    $userFontReg = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"

    # 1) Make sure the font is really installed (winget may have skipped/failed).
    $fontPresent = $false
    foreach ($rp in @($userFontReg, "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts")) {
        if (Test-Path $rp) {
            if ((Get-ItemProperty $rp).PSObject.Properties.Name -like 'JetBrainsMono*') { $fontPresent = $true; break }
        }
    }
    if ($fontPresent) {
        Write-Host "  Font already installed." -ForegroundColor DarkGray
    } else {
        try {
            Write-Host "  Font missing - installing from nerd-fonts releases (no admin needed)..." -ForegroundColor DarkGray
            $zip    = Join-Path $env:TEMP "JetBrainsMonoNF.zip"
            $tmpDir = Join-Path $env:TEMP "JetBrainsMonoNF"
            if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
            Invoke-WebRequest -Uri "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" -OutFile $zip -UseBasicParsing
            Expand-Archive -Path $zip -DestinationPath $tmpDir -Force
            $fontDst = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
            New-Item -ItemType Directory -Force -Path $fontDst | Out-Null
            if (-not (Test-Path $userFontReg)) { New-Item -Path $userFontReg -Force | Out-Null }
            $ttfs = @(Get-ChildItem -Path $tmpDir -Recurse -Filter *.ttf)
            $copied = 0; $inUse = 0
            foreach ($f in $ttfs) {
                $dst = Join-Path $fontDst $f.Name
                try {
                    Copy-Item $f.FullName $dst -Force -ErrorAction Stop
                    Set-ItemProperty -Path $userFontReg -Name "$($f.BaseName) (TrueType)" -Value $dst
                    $copied++
                } catch {
                    # File already present and locked by the font cache / a running
                    # terminal. It is already installed, so skipping is harmless.
                    $inUse++
                }
            }
            Write-Host "  Installed $copied font file(s) for the current user ($inUse already in use, skipped)." -ForegroundColor DarkGray
        } catch {
            Write-Host "  Could not auto-install the font: $($_.Exception.Message)" -ForegroundColor DarkGray
            Write-Host "  Get it manually from https://www.nerdfonts.com" -ForegroundColor DarkGray
        }
    }

    # 2) Apply to Windows Terminal (all known settings.json locations).
    $wtPaths = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )
    $wtSeen = @{}
    $wtDone = 0
    foreach ($p in $wtPaths) {
        if (-not (Test-Path $p)) { continue }
        # Skip paths that resolve to a file already handled (symlink/duplicate).
        $full = (Get-Item $p).FullName
        if ($wtSeen[$full]) { continue }
        $wtSeen[$full] = $true
        try {
            $cfg = Get-Content $p -Raw | ConvertFrom-Json -ErrorAction Stop
            if (-not $cfg.profiles) { continue }
            Copy-Item $p "$p.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')" -Force
            if (-not $cfg.profiles.defaults) {
                $cfg.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            if (-not $cfg.profiles.defaults.font) {
                $cfg.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            $cfg.profiles.defaults.font | Add-Member -NotePropertyName face -NotePropertyValue $face -Force
            $cfg | ConvertTo-Json -Depth 32 | Set-Content $p -Encoding utf8
            $wtDone++
        } catch {
            Write-Host "  Could not auto-edit $p (set the font manually)." -ForegroundColor DarkGray
        }
    }
    if ($wtDone -gt 0) {
        Write-Host "  Windows Terminal font set to '$face' in $wtDone settings file(s)." -ForegroundColor DarkGray
    }

    # 3) Apply to the legacy console (conhost) default - covers the plain
    #    'Windows PowerShell' window. Uses the monospaced NF variant.
    try {
        if (-not (Test-Path "HKCU:\Console")) { New-Item -Path "HKCU:\Console" -Force | Out-Null }
        New-ItemProperty -Path "HKCU:\Console" -Name "FaceName"   -Value $faceMono -PropertyType String -Force | Out-Null
        New-ItemProperty -Path "HKCU:\Console" -Name "FontFamily" -Value 54        -PropertyType DWord  -Force | Out-Null
        New-ItemProperty -Path "HKCU:\Console" -Name "FontWeight" -Value 400       -PropertyType DWord  -Force | Out-Null
        Write-Host "  Legacy console default font set to '$faceMono'." -ForegroundColor DarkGray
    } catch {
        Write-Host "  Could not set legacy console font automatically." -ForegroundColor DarkGray
    }
    Write-Host "  Restart your terminal to see the new font." -ForegroundColor DarkGray
}

# ── Claude Code plugins (manual, after login) ─────────────
Write-Host ""
Write-Host "-- Claude Code plugins (run after login) --" -ForegroundColor Yellow
Write-Host "  claude auth login"
Write-Host "  claude plugin marketplace add Yeachan-Heo/oh-my-claudecode"
Write-Host "  claude plugin install oh-my-claudecode@omc"
Write-Host "  claude plugin marketplace add openai/codex-plugin-cc"
Write-Host "  claude plugin install codex@openai-codex"
Write-Host "  claude plugin marketplace add https://github.com/orientpine/honeypot.git"
Write-Host "  claude plugin marketplace add forrestchang/andrej-karpathy-skills"
Write-Host "  claude plugin install andrej-karpathy-skills@karpathy-skills"
Write-Host "-------------------------------------------" -ForegroundColor Yellow

# ── Summary ───────────────────────────────────────────────
Write-Host ""
if ($DryRun) {
    Write-Host "[DRY-RUN] Plan validated - nothing was installed." -ForegroundColor Green
} elseif ($failedPkgs.Count -eq 0) {
    Write-Host "All required packages installed successfully." -ForegroundColor Green
} else {
    Write-Host "Done with $($failedPkgs.Count) issue(s):" -ForegroundColor Yellow
    foreach ($f in $failedPkgs) {
        Write-Host "  [FAILED] $f" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Tip: For 'Store conflict' errors, uninstall the Microsoft Store version first," -ForegroundColor DarkGray
    Write-Host "     then re-run this script and select only the failed packages." -ForegroundColor DarkGray
    Write-Host ""

    # ── Report a problem (terminal-friendly) ──────────────────
    # 1) Pre-filled GitHub issue URL: opens the browser with the OS, the failed
    #    items and the log path already filled in, so the user only presses Submit.
    # 2) gh (already installed by this script): if present and interactive, offer
    #    to file the issue straight from the terminal.
    $reportTitle = "[install] $($failedPkgs.Count) issue(s) on Windows"
    $reportBody = @"
## 환경 (Environment)
- OS: Windows $([Environment]::OSVersion.Version)
- PowerShell: $($PSVersionTable.PSVersion)

## 실패 항목 (Failed items)
$(( $failedPkgs | ForEach-Object { "- $_" } ) -join "`n")

## 로그 (Logs)
- $env:TEMP\omc-install-*.log

## 추가 상황 (Notes)
<!-- 무엇을 하다 생긴 문제인지 적어주세요 -->
"@
    $issueUrl = "https://github.com/hd0126/dev-setup/issues/new?title=$([uri]::EscapeDataString($reportTitle))&body=$([uri]::EscapeDataString($reportBody))"

    Write-Host "문제를 알려주세요 (초보 환영):" -ForegroundColor Cyan
    Write-Host "  아래 링크를 열면 OS·에러·로그 경로가 자동으로 채워집니다 (Submit만 누르면 끝):" -ForegroundColor DarkGray
    Write-Host "  $issueUrl" -ForegroundColor Cyan
    Write-Host "  (로그 파일: $env:TEMP\omc-install-*.log)" -ForegroundColor DarkGray

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($gh -and -not $NonInteractive) {
        Write-Host ""
        $ans = Read-Host "  gh가 설치돼 있습니다. 지금 바로 이슈를 생성할까요? (gh 로그인 필요) [y/N]"
        if ($ans -match '^(y|yes)$') {
            $tmpBody = Join-Path $env:TEMP "devsetup-issue-body.md"
            $reportBody | Out-File -FilePath $tmpBody -Encoding utf8
            & $gh.Source issue create --repo hd0126/dev-setup --title $reportTitle --body-file $tmpBody
            if ($LASTEXITCODE -eq 0) { Write-Host "  이슈가 생성되었습니다. 감사합니다!" -ForegroundColor Green }
            else { Write-Host "  gh 제출 실패 — 위 링크로 열어주세요 ('gh auth login' 후 재시도 가능)." -ForegroundColor DarkGray }
            Remove-Item $tmpBody -Force -ErrorAction SilentlyContinue
        }
    }
}

# Dry-run ends here: the plan was printed, the post-install steps below don't apply.
if ($DryRun) {
    Write-Host ""
    if ($RunAsFile) { exit 0 }   # 파일 실행(CI 포함): 종료 코드 유지
    return                       # irm | iex: exit는 터미널 세션을 닫으므로 return
}

# Optional extras (fonts) - informational only, never a real failure
if ($optionalFails.Count -gt 0) {
    Write-Host ""
    Write-Host "Optional items skipped (not required - safe to ignore):" -ForegroundColor DarkGray
    foreach ($o in $optionalFails) { Write-Host "  [skip] $o" -ForegroundColor DarkGray }
    Write-Host "  A Nerd Font can be installed manually from https://www.nerdfonts.com" -ForegroundColor DarkGray
}

# Native-module build failures (e.g. oh-my-claude-sisyphus -> better-sqlite3)
if ($npmNativeFail) {
    Write-Host ""
    Write-Host "An npm package failed to build a native module (e.g. better-sqlite3)." -ForegroundColor Yellow
    Write-Host "This needs the C++ build tools. Fix it with:" -ForegroundColor DarkGray
    Write-Host '  winget install Microsoft.VisualStudio.2022.BuildTools --silent --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"' -ForegroundColor DarkGray
    Write-Host "  # then open a NEW terminal and re-run the failed npm install, e.g.:" -ForegroundColor DarkGray
    Write-Host "  npm install -g oh-my-claude-sisyphus" -ForegroundColor DarkGray
    Write-Host "If you are behind a corporate proxy/firewall, prebuilt binaries may be blocked;" -ForegroundColor DarkGray
    Write-Host "configure npm proxy (npm config set proxy ...) or try another network." -ForegroundColor DarkGray
}

# Network/proxy failures (corporate firewall blocking npm downloads)
if ($npmNetworkFail) {
    Write-Host ""
    Write-Host "An npm package failed to download (network/proxy/firewall)." -ForegroundColor Yellow
    Write-Host "If you are behind a corporate proxy, point npm at it and retry:" -ForegroundColor DarkGray
    Write-Host "  npm config set proxy http://<proxy-host>:<port>" -ForegroundColor DarkGray
    Write-Host "  npm config set https-proxy http://<proxy-host>:<port>" -ForegroundColor DarkGray
    Write-Host "Otherwise check your connection or try another network, then open a NEW" -ForegroundColor DarkGray
    Write-Host "terminal and re-run this script (already-installed items are skipped)." -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  NEXT STEP: Open a NEW pwsh (PowerShell 7)" -ForegroundColor Cyan
Write-Host "  window NOW to apply PATH and profile."      -ForegroundColor Cyan
Write-Host "  claude / codex will NOT work until you do." -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Nerd Font was installed and set as the terminal font automatically." -ForegroundColor DarkGray
Write-Host "If icons still look broken after restarting, set the font by hand:" -ForegroundColor DarkGray
Write-Host "  Windows Terminal : Settings > Defaults > Appearance > Font face > 'JetBrainsMono Nerd Font'" -ForegroundColor DarkGray
Write-Host "  Legacy console   : title bar > Properties > Font > 'JetBrainsMono Nerd Font Mono'" -ForegroundColor DarkGray
