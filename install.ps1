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

# 한글/공백 계정명이면 $env:TEMP 가 8.3 짧은 이름(C:\Users\곽대운~1\...)이 되는데,
# Remove-Item 은 이 경로의 "존재하는" 항목을 지우지 못하고 -ErrorAction 도 무시한 채
# "지정한 경로 ...~1에 개체가 없습니다" 를 낸다(-LiteralPath 도 동일, PS 5.1·7 공통).
# Get-Item 으로 긴 경로를 얻은 뒤 지운다. 없는 경로는 조용히 건너뛴다.
function Remove-TempPath {
    param([string[]]$Path, [switch]$Recurse)
    foreach ($p in $Path) {
        try { $full = (Get-Item -LiteralPath $p -Force -ErrorAction Stop).FullName } catch { continue }
        Remove-Item -LiteralPath $full -Recurse:$Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 사용자 PATH 원문을 레지스트리에서 직접 읽고 쓴다.
# [Environment]::GetEnvironmentVariable 은 %JAVA_HOME%\bin 같은 항목을 확장해서 돌려준다.
# 그 값을 그대로 다시 쓰면 그 항목들이 오늘의 값으로 굳는다 (REG_EXPAND_SZ -> REG_SZ).
# Windows 기본 항목 %USERPROFILE%\AppData\Local\Microsoft\WindowsApps 도 같은 피해를 본다.
# 그래서 확장하지 않은 원문과 값 종류를 그대로 보존한다.
function Get-UserPathRaw {
    $raw  = ''
    $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
    $key  = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    if ($key) {
        try {
            if ($key.GetValueNames() -contains 'Path') {
                $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                $k   = $key.GetValueKind('Path')
                if ($k -eq [Microsoft.Win32.RegistryValueKind]::String) { $kind = $k }
            }
        } finally { $key.Close() }
    }
    return @{ Value = $raw; Kind = $kind }
}

function Set-UserPathRaw {
    param([string]$Value, $Kind)
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    try { $key.SetValue('Path', $Value, $Kind) } finally { $key.Close() }
    # 레지스트리 직접 쓰기는 변경 알림(WM_SETTINGCHANGE)을 보내지 않는다. 존재하지 않는
    # 변수를 지우는 무해한 호출로 알림만 발생시켜, 새로 여는 터미널이 바뀐 PATH 를 받게 한다.
    try { [Environment]::SetEnvironmentVariable('DEVSETUP_PATH_REFRESH', $null, 'User') } catch {}
}

# 사용자 PATH(레지스트리)와 현재 세션 PATH에 폴더를 멱등하게 추가한다. 관리자 권한 불필요.
# 사용자 PATH가 실제로 바뀌었으면 $true 를 돌려준다.
#
# -BeforeStoreAliases: Windows 의 "앱 실행 별칭" 폴더(...\Microsoft\WindowsApps)보다
# 앞에 오도록 맨 앞에 둔다. 그 폴더의 python.exe 는 Microsoft Store 를 여는 스텁이라,
# 우리 폴더가 뒤에 있으면 `python` 을 쳤을 때 설치한 Python 대신 스텁이 잡힌다.
function Add-UserPath {
    param([string]$Dir, [switch]$BeforeStoreAliases)
    $want  = $Dir.TrimEnd('\')
    $cur   = Get-UserPathRaw
    $parts = @($cur.Value -split ';' | Where-Object { $_ })
    $idx = -1; $storeIdx = -1
    for ($i = 0; $i -lt $parts.Count; $i++) {
        # 비교는 확장한 값으로, 저장은 원문 그대로 (%USERPROFILE%\... 항목 보존).
        $p = [Environment]::ExpandEnvironmentVariables($parts[$i]).TrimEnd('\')
        if ($idx -lt 0 -and $p -ieq $want) { $idx = $i }
        if ($storeIdx -lt 0 -and $p -like '*\Microsoft\WindowsApps') { $storeIdx = $i }
    }

    $newParts = $null
    if ($idx -lt 0) {
        $newParts = if ($BeforeStoreAliases) { @($Dir) + $parts } else { $parts + @($Dir) }
    } elseif ($BeforeStoreAliases -and $storeIdx -ge 0 -and $idx -gt $storeIdx) {
        $rest = @(for ($i = 0; $i -lt $parts.Count; $i++) { if ($i -ne $idx) { $parts[$i] } })
        $newParts = @($Dir) + $rest
    }
    $changed = ($null -ne $newParts)
    if ($changed) { Set-UserPathRaw -Value ($newParts -join ';') -Kind $cur.Kind }

    $sessionParts = @($env:Path -split ';' | ForEach-Object { $_.TrimEnd('\') })
    if ($BeforeStoreAliases) {
        if ($sessionParts.Count -eq 0 -or $sessionParts[0] -ine $want) { $env:Path = "$Dir;$env:Path" }
    } elseif ($sessionParts -inotcontains $want) {
        $env:Path = $env:Path.TrimEnd(';') + ";$Dir"
    }
    return $changed
}

# Remove an npm-installed copy of a tool that now has a native install (claude, codex).
# Which copy runs depends on PATH order, and that order differs between contexts: for
# Claude Code this script appends ~\.local\bin to the END of the user PATH (unless the uv
# step later moves it to the front), so on a PC where Node's %APPDATA%\npm came first, a
# leftover npm copy wins in new terminals. Detected with `npm ls`, not Get-Command,
# because the first hit depends on the current PATH.
# Same tool, same vendor, so no prompt. Call it only AFTER the native binary exists, and
# it refuses unless the native folder is on the persistent (user or machine) PATH -
# otherwise removing the npm copy would leave no `claude`/`codex` in new terminals.
# Returns $true when it printed something, so the caller can fix its progress line.
function Remove-NpmDuplicate {
    param([string]$NpmName, [string]$Cmd, [string]$NativeDir)
    if (-not $NpmName) { return $false }
    $npm = Get-Command npm.cmd -CommandType Application -ErrorAction SilentlyContinue
    if (-not $npm) { return $false }
    $ls  = & $npm.Source ls -g $NpmName --depth=0 --json 2>$null | Out-String
    $has = $false
    try {
        $deps = ($ls | ConvertFrom-Json).dependencies
        $has  = [bool]($deps -and $deps.PSObject.Properties[$NpmName])
    } catch {}
    if (-not $has) { return $false }
    $want   = [Environment]::ExpandEnvironmentVariables($NativeDir).TrimEnd('\')
    $onPath = $false
    foreach ($scope in 'User', 'Machine') {
        foreach ($p in @([Environment]::GetEnvironmentVariable('Path', $scope) -split ';')) {
            if ($p -and ([Environment]::ExpandEnvironmentVariables($p).TrimEnd('\') -ieq $want)) { $onPath = $true }
        }
    }
    if (-not $onPath) {
        Write-Host ""
        Write-Host "  kept the npm copy of ${Cmd} - the native folder ($NativeDir) is not on your PATH yet." -ForegroundColor Yellow
        return $true
    }
    Write-Host ""
    Write-Host "  removing duplicate npm copy of $Cmd ($NpmName) - the native install replaces it..." -ForegroundColor Yellow -NoNewline
    $null = & $npm.Source uninstall -g $NpmName 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { Write-Host " done" -ForegroundColor Green }
    else { Write-Host " failed (npm exit $LASTEXITCODE). Remove it later:  npm uninstall -g $NpmName" -ForegroundColor Yellow }
    return $true
}

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
        Desc = "JS runtime. Keep this on: the omc plugin's hooks, omx and npx-based MCP servers all run on Node (Claude Code itself is native)."
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
    # Off by default on Windows: the profile draws its own pure-PowerShell prompt and
    # never uses Starship. Enabling Starship runs an external exe on every prompt, which
    # measured 1.6-2.0 s per prompt on a PC with real-time antivirus scanning
    # (pure-PS prompt: 17-103 ms). Still selectable for people who want it.
    @{
        Id   = "Starship.Starship"
        Name = "Starship"
        Desc = "Optional prompt (off by default). This profile uses its own faster pure-PS prompt; Starship stays idle until you enable it (see README)."
        Ex   = "'Invoke-Expression (&starship init powershell)' | Add-Content `$PROFILE"
        On   = $false
    },
    # Keep on even without Starship: the legacy console's default font (Consolas) has
    # no glyph for the prompt arrow U+276F, so it shows as a box there. Windows
    # Terminal's default (Cascadia Mono) has it; the Nerd Font covers both.
    @{
        Id       = "DEVCOM.JetBrainsMonoNerdFont"
        Name     = "JetBrainsMono Nerd Font"
        Desc     = "Prevents broken glyphs: the prompt arrow in the old console window, plus icons for Starship/eza."
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
    # "Comfort plus" tools, same set as macOS/Linux. Optional = a failed install is
    # reported as skipped, never as a failure of the whole run. IDs are the ones the
    # projects themselves publish (checked with `winget show --id <id> --exact`).
    @{
        Id       = "eza-community.eza"
        Name     = "eza"
        Desc     = "Modern ls. The profile adds ll / la / lt."
        Ex       = "ll  /  la  /  lt (tree)"
        On       = $true
        Optional = $true
    },
    @{
        Id       = "sharkdp.bat"
        Name     = "bat"
        Desc     = "cat with syntax highlighting. Run it as 'bat' (PowerShell's own cat is left alone)."
        Ex       = "bat README.md"
        On       = $true
        Optional = $true
    },
    @{
        Id       = "sharkdp.fd"
        Name     = "fd"
        Desc     = "Fast find that respects .gitignore. Also speeds up fzf's Ctrl+T file search."
        Ex       = "fd .ps1"
        On       = $true
        Optional = $true
    },
    @{
        Id       = "dandavison.delta"
        Name     = "delta"
        Desc     = "Readable git diff. Set as git's pager unless you already have one."
        Ex       = "git diff"
        On       = $true
        Optional = $true
    },
    @{
        Id       = "dbrgn.tealdeer"
        Name     = "tldr (tealdeer)"
        Desc     = "Short, example-first command help."
        Ex       = "tldr tar"
        On       = $true
        Optional = $true
    },
    # Python 은 winget 으로 특정 버전을 고정 설치하지 않는다. 고정값은 금방 낡는다.
    # (3.12 고정이 3.15 시대까지 남아 있었다.) uv 가 최신 Python 을 직접 받아 관리한다.
    # 아래 "Python via uv" 단계 참고. 버전 하드코딩 금지.
    @{
        Id   = "astral-sh.uv"
        Name = "uv + Python"
        Desc = "Fast Python manager (pip/venv replacement). Also installs the latest Python itself (uv python install)."
        Ex   = "python --version / uv venv / uv pip install <pkg>"
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
    # Gemini CLI(@google/gemini-cli)의 후속. Google 이 2026-06-18 부터 무료/Pro/Ultra
    # 계정의 Gemini CLI 요청을 받지 않아(유료 API 키만 유지) Antigravity CLI 로 교체했다.
    @{
        Name      = "Antigravity CLI (Google)"
        Desc      = "Google's terminal coding agent (agy) - successor to Gemini CLI. Native installer, no Node dependency, self-updating."
        Ex        = "agy"
        On        = $true
        Native    = $true
        Installer = "https://antigravity.google/cli/install.ps1"
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

# The omc plugin is installed by hand after this script (not in the menu), so the rule
# above cannot see it. Its hooks and MCP server run `node`, so warn - without forcing it
# back on - when Node was unchecked and is not on this PC already.
$nodePkgSel = $packages | Where-Object { $_.Name -eq "Node.js LTS" }
if ($nodePkgSel -and -not $nodePkgSel.On -and -not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "Warning: Node.js is not selected and not installed." -ForegroundColor Yellow
    Write-Host "  The omc (oh-my-claudecode) plugin's hooks, omx and npx-based MCP servers need Node." -ForegroundColor DarkGray
    Write-Host "  Claude Code itself works without it. To add it later:  winget install OpenJS.NodeJS.LTS" -ForegroundColor DarkGray
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

# One winget scan instead of one `winget list` per package. Each `winget list --id`
# rescans everything installed (measured ~14 s per call on a PC with real-time
# antivirus); `winget export` scans once (~57 s there for 104 packages, vs ~139 s for
# 10 separate lists) and writes JSON, so the result does not depend on the UI language
# or on column truncation. Any failure falls back to the old per-package check.
$installedIds = $null   # PackageIdentifier -> source name ('winget' / 'msstore'); $null = unknown
if (-not $DryRun -and $wingetList.Count -gt 0) {
    Write-Host "Checking what is already installed (one winget scan, can take a minute)..." -ForegroundColor DarkGray
    $expFile = Join-Path $env:TEMP "devsetup-winget-export-$PID.json"
    try {
        winget export -o $expFile --accept-source-agreements 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0 -and (Test-Path $expFile)) {
            $exp = Get-Content $expFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $scan = @{}
            foreach ($src in @($exp.Sources)) {
                foreach ($p in @($src.Packages)) { $scan[[string]$p.PackageIdentifier] = [string]$src.SourceDetails.Name }
            }
            $installedIds = $scan
        }
    } catch {
        $installedIds = $null
    } finally {
        Remove-TempPath $expFile
    }
}

foreach ($pkg in $wingetList) {
    $wingetIdx++
    Write-Host "[$wingetIdx/$wingetTotal] $($pkg.Name)..." -ForegroundColor Cyan -NoNewline
    if ($DryRun) { Write-Host " [DRY-RUN] would install/upgrade ($($pkg.Id))" -ForegroundColor DarkGray; continue }

    # Check if already installed, and from which source
    if ($null -ne $installedIds) {
        $alreadyInstalled = $installedIds.ContainsKey($pkg.Id)
        $isStoreManaged   = $alreadyInstalled -and ($installedIds[$pkg.Id] -eq 'msstore')
    } else {
        $listOut = winget list --id $pkg.Id --exact --accept-source-agreements 2>&1 | Out-String
        $alreadyInstalled = ($LASTEXITCODE -eq 0)
        $isStoreManaged   = $alreadyInstalled -and ($listOut -match 'msstore|Microsoft Store')
    }

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
    } elseif ($alreadyInstalled) {
        # 업그레이드 실패지만 기존 버전이 이미 설치·동작 중이므로 치명적 실패가 아니다.
        # (winget 업그레이드는 설치기 이슈로 0x8A150006 등으로 자주 실패한다. 예: Git)
        $hex = if ($exit -lt 0) { '0x{0:X8}' -f [uint32]([long]$exit + 4294967296) } else { '0x{0:X8}' -f [uint32]$exit }
        Write-Host " [OK - kept installed version (upgrade skipped: exit $exit / $hex)]" -ForegroundColor Green
    } else {
        $hex = if ($exit -lt 0) { '0x{0:X8}' -f [uint32]([long]$exit + 4294967296) } else { '0x{0:X8}' -f [uint32]$exit }
        $reason = switch ($exit) {
            1603        { "installer conflict (exit 1603)" }
            -1073741819 { "installer crashed (0xC0000005 access violation - often antivirus or a broken VC++ runtime)" }
            5           { "access denied (exit 5 - try running this script once as Administrator)" }
            default     { "exit $exit ($hex)" }
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

# ── delta as git pager / tldr page cache (same as macOS/Linux) ──
# delta: only when no pager is configured at ANY level (system/global/local config, or
#   GIT_PAGER / PAGER) - an existing choice is the user's. diffFilter likewise only if unset.
# tldr: tealdeer ships without pages; fetch them when `tldr --list` has nothing yet, so
#   a failed first download is retried on the next run.
# -CommandType Application: never pick up a user's function/alias named git/delta/tldr.
if (-not $DryRun) {
    $deltaPkg = $packages | Where-Object { $_.Id -eq 'dandavison.delta' }
    $gitCmd   = Get-Command git   -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $deltaCmd = Get-Command delta -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($deltaPkg -and $deltaPkg.On -and $gitCmd -and $deltaCmd) {
        $curPager = (& $gitCmd.Source config core.pager 2>$null | Out-String).Trim()
        if (-not $curPager) { $curPager = "$env:GIT_PAGER".Trim() }
        if (-not $curPager) { $curPager = "$env:PAGER".Trim() }
        if ($curPager -eq 'delta') {
            Write-Host "git pager: delta (already set)" -ForegroundColor DarkGray
        } elseif ($curPager) {
            Write-Host "git pager: kept your existing setting ($curPager)" -ForegroundColor DarkGray
        } else {
            & $gitCmd.Source config --global core.pager delta
            $curFilter = (& $gitCmd.Source config interactive.diffFilter 2>$null | Out-String).Trim()
            if (-not $curFilter) { & $gitCmd.Source config --global interactive.diffFilter "delta --color-only" }
            Write-Host "git pager: delta (highlighted git diff)" -ForegroundColor DarkGray
        }
    }
    $tldrPkg = $packages | Where-Object { $_.Id -eq 'dbrgn.tealdeer' }
    $tldrCmd = Get-Command tldr -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($tldrPkg -and $tldrPkg.On -and $tldrCmd) {
        $tldrPages = (& $tldrCmd.Source --list 2>$null | Select-Object -First 1)
        if (-not $tldrPages) {
            & $tldrCmd.Source --update 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Host "tldr: page cache downloaded" -ForegroundColor DarkGray }
            else { Write-Host "tldr: page download failed - it is retried on the next run (or run 'tldr --update')" -ForegroundColor DarkGray }
        }
    }
}

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
        Remove-TempPath $dir -Recurse
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $dir -Force
        $exe = Get-ChildItem -Path $dir -Recurse -Filter 'zoxide.exe' | Select-Object -First 1
        if (-not $exe) { throw "zoxide.exe not found in archive" }
        $binDir = Join-Path $env:LOCALAPPDATA 'Programs\zoxide'
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null
        Copy-Item $exe.FullName (Join-Path $binDir 'zoxide.exe') -Force
        # Persist on the user PATH (no admin needed) and add to the current session.
        Add-UserPath $binDir | Out-Null
        $failedPkgs = @($failedPkgs | Where-Object { $_ -notlike 'zoxide*' })
        Write-Host "  zoxide $($rel.tag_name) installed to $binDir and added to PATH." -ForegroundColor Green
    } catch {
        Write-Host "  zoxide fallback failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Install manually from https://github.com/ajeetdsouza/zoxide/releases" -ForegroundColor DarkGray
    }
}

# ── Python via uv ─────────────────────────────────────────
# winget 으로 Python 버전을 고정 설치하는 대신 uv 가 최신 Python 을 받아 관리한다.
# --default 는 버전 명령(python3.x) 외에 `python`/`python3` 까지 만든다.
#   * 이미 진짜 Python 이 PATH 에 있으면(스토어 스텁·uv 관리본 제외) 그대로 둔다 -
#     기본 python 을 말없이 바꾸면 기존 전역 패키지 환경이 깨질 수 있다.
#   * 실행 파일은 ~\.local\bin 에 놓이므로 스토어 스텁보다 앞에 오도록 PATH 를 맞춘다.
$uvPkg = $packages | Where-Object { $_.Id -eq 'astral-sh.uv' }
if ($uvPkg -and $uvPkg.On) {
    Write-Host "Python (latest, managed by uv)..." -ForegroundColor Cyan -NoNewline
    $localBin = Join-Path $env:USERPROFILE '.local\bin'
    $uvCmd    = Get-Command uv -ErrorAction SilentlyContinue
    if ($DryRun) {
        Write-Host " [DRY-RUN] would run: uv python install --default" -ForegroundColor DarkGray
    } elseif (-not $uvCmd) {
        # uv 설치 실패는 위 winget 단계에서 이미 실패 목록에 들어갔다 - 중복 집계하지 않는다.
        Write-Host " [SKIP] uv not found" -ForegroundColor Yellow
    } else {
        # ...\Microsoft\WindowsApps\python.exe 는 두 가지일 수 있다: Store 를 여는 빈 스텁,
        # 또는 Microsoft Store / Python Install Manager 로 설치한 진짜 Python 의 별칭.
        # 경로만으로는 구별이 안 되므로 실제로 --version 을 돌려 본다 (스텁은 exit 9009).
        $realPy = $null
        foreach ($cand in @(Get-Command python -All -ErrorAction SilentlyContinue)) {
            $src = $cand.Source
            if (-not $src -or $src -like "$localBin\*") { continue }
            if ($src -like '*\Microsoft\WindowsApps\*') {
                $isReal = $false
                try {
                    $verOut = (& $src --version 2>&1 | Out-String)
                    $isReal = ($LASTEXITCODE -eq 0 -and $verOut -match 'Python \d+\.\d+')
                } catch {}
                if (-not $isReal) { continue }
            }
            $realPy = $cand; break
        }
        if ($realPy) {
            Write-Host " [OK - existing Python kept: $($realPy.Source)]" -ForegroundColor Green
            Write-Host "  To switch to the latest later:  uv python install --default" -ForegroundColor DarkGray
        } else {
            $withDefault = $true
            $pyOut = & $uvCmd.Source python install --default 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                # 구버전 uv 등 --default 를 못 쓰는 환경: 버전 명령만 만드는 기본 설치로 폴백.
                $withDefault = $false
                $pyOut = & $uvCmd.Source python install 2>&1 | Out-String
            }
            if ($LASTEXITCODE -eq 0) {
                Add-UserPath $localBin -BeforeStoreAliases | Out-Null
                $pyExe = Join-Path $localBin 'python.exe'
                $pyVer = if (Test-Path $pyExe) { (& $pyExe --version 2>&1 | Out-String).Trim() } else { '' }
                if ($withDefault -and $pyVer) {
                    Write-Host " [OK - $pyVer]" -ForegroundColor Green
                } else {
                    Write-Host " [OK]" -ForegroundColor Green
                    Write-Host "  'python' shortcut was not created - run Python with:  uv run python" -ForegroundColor DarkGray
                }
            } else {
                Write-Host " [FAILED] exit $LASTEXITCODE" -ForegroundColor Red
                $failedPkgs += "Python via uv (exit $LASTEXITCODE)"
                $pyLog = Join-Path $env:TEMP 'omc-install-python-uv.log'
                $pyOut | Out-File -FilePath $pyLog -Encoding utf8
                Write-Host "    full log saved to: $pyLog" -ForegroundColor DarkGray
            }
        }
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
            # 실제 설치 경로는 도구마다 다르다: Claude Code 는 ~/.local\bin\claude.exe,
            # codex 는 %LOCALAPPDATA%\Programs\OpenAI\Codex\bin\codex.exe 에 설치된다.
            # (이전엔 codex 도 ~/.local\bin 으로 잘못 확인해 항상 재설치를 시도했다.)
            # Antigravity CLI 는 %LOCALAPPDATA%\agy\bin\agy.exe (공식 install.ps1 의 TARGET_DIR).
            if ($pkg.Name -eq 'Claude Code') {
                $nativeBin = Join-Path $env:USERPROFILE '.local\bin\claude.exe'
                $nativeCmd = 'claude'; $npmName = '@anthropic-ai/claude-code'
            } elseif ($pkg.Name -like 'Antigravity*') {
                $nativeBin = Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe'
                $nativeCmd = 'agy';    $npmName = $null   # npm 판이 없다 (Gemini CLI 는 별개 패키지)
            } else {
                $nativeBin = Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'
                $nativeCmd = 'codex';  $npmName = '@openai/codex'
            }
            # 아래 symlink 우회·standalone 정리 재시도는 codex 전용이다.
            # 이름 비교를 "Claude Code 가 아니면"으로 하면, 다른 네이티브 도구 설치가
            # 실패했을 때 멀쩡한 Codex 설치 폴더를 지우게 된다. codex 여부를 명시적으로 판별한다.
            $isCodex = ($nativeCmd -eq 'codex')

            # 이미 네이티브로 설치돼 있으면 대용량 재다운로드 skip — 네이티브 빌드는
            # 백그라운드 자동 업데이트가 있어 기존 설치로 충분 (mac/linux와 동일 동작)
            # A leftover npm copy is removed on BOTH paths: before this, the cleanup only ran
            # on a fresh native install, so a PC that already had the native build kept its
            # npm copy forever (and it could shadow the native one, see Remove-NpmDuplicate).
            if (Test-Path $nativeBin) {
                $nativeDir = Split-Path $nativeBin
                # Claude's native installer never adds ~\.local\bin to PATH (codex's and
                # agy's do). Make sure it is there before the npm copy can be removed.
                if (-not $isCodex) { $null = Add-UserPath $nativeDir }
                if (Remove-NpmDuplicate $npmName $nativeCmd $nativeDir) {
                    Write-Host "  -> $($pkg.Name) [OK - native install kept (self-updating)]" -ForegroundColor Green
                } else {
                    Write-Host " [OK - already installed (native, self-updating)]" -ForegroundColor Green
                }
                continue
            }

            Write-Host ""
            $tmp       = Join-Path $env:TEMP "devsetup-native-$npmIdx.ps1"
            $nativeLog = Join-Path $env:TEMP ("omc-install-" + ($pkg.Name -replace '[^\w.-]','_') + ".log")

            # 프로필 경로가 심볼릭 링크/정션이면(예: 한글 계정명을 ASCII 로 우회한 경우)
            # codex 의 tar 압축 해제가 "Cannot extract through symlink" 로 거부된다.
            # 링크가 해석된 실제 경로를 CODEX_HOME/TEMP 로 넘겨 tar 가 링크를 통과하지
            # 않게 한다. 두 경로는 물리적으로 같은 폴더라 codex 런타임엔 영향이 없다.
            $profItem = Get-Item $env:USERPROFILE -Force -ErrorAction SilentlyContinue
            $profReal = if ($profItem -and $profItem.Target) { [string]$profItem.Target } else { $env:USERPROFILE }
            $profileIsLink = ($profReal -ne $env:USERPROFILE)

            $savedTemp = $env:TEMP; $savedTmp = $env:TMP
            $savedCodexHome = $env:CODEX_HOME; $savedNI = $env:CODEX_NON_INTERACTIVE
            $env:CODEX_NON_INTERACTIVE = '1'   # "Start Codex now?" Read-Host 멈춤 방지
            if ($isCodex -and $profileIsLink) {
                $env:CODEX_HOME = Join-Path $profReal '.codex'
                $realTemp = Join-Path $profReal 'AppData\Local\Temp'
                if (Test-Path $realTemp) { $env:TEMP = $realTemp; $env:TMP = $realTemp }
            }

            try {
                Invoke-RestMethod $pkg.Installer -OutFile $tmp
                # 출력을 캡처(=리다이렉트)하면 프롬프트도 자동 우회되고, 실패 시 실제
                # 원인(tar/symlink/네트워크)을 로그로 남겨 이슈 리포트에 담을 수 있다.
                $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp 2>&1 | Out-String
                $out | Out-File -FilePath $nativeLog -Encoding utf8
                if ($out.Trim()) { Write-Host $out.TrimEnd() -ForegroundColor DarkGray }

                # codex 에 표기 충돌(ASCII vs 한글)로 남은 옛 정션이 있으면 "Refusing to
                # retarget junction" 으로 실패한다. standalone 을 정리하고 1회 재시도.
                if ($isCodex -and -not (Test-Path $nativeBin) -and $profileIsLink) {
                    Write-Host "  retry (clean standalone)..." -ForegroundColor DarkGray
                    Remove-Item (Join-Path $env:CODEX_HOME 'packages\standalone') -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item (Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex') -Recurse -Force -ErrorAction SilentlyContinue
                    $out2 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp 2>&1 | Out-String
                    $out2 | Out-File -FilePath $nativeLog -Encoding utf8 -Append
                    if ($out2.Trim()) { Write-Host $out2.TrimEnd() -ForegroundColor DarkGray }
                }

                # 성공 판정은 exit code 가 아니라 실제 바이너리 존재로 한다 — 네이티브
                # 설치기가 성공해도 비정상 종료 코드를 남기는 경우가 있어 오탐을 막는다.
                if (Test-Path $nativeBin) {
                    Write-Host "  -> $($pkg.Name) [OK - native installer]" -ForegroundColor Green
                    # Claude Code's Windows native installer drops claude.exe in
                    # %USERPROFILE%\.local\bin but, unlike codex, does NOT add that
                    # folder to PATH. Persist it (and add to this session) so the
                    # `claude` command resolves after install / in a new terminal.
                    # Antigravity's installer hands PATH setup to `agy install`; the same
                    # idempotent call is a safety net in case that step was skipped.
                    $nativeDir = Split-Path $nativeBin
                    if (-not $isCodex) {
                        if (Add-UserPath $nativeDir) {
                            Write-Host "     added $nativeDir to your PATH" -ForegroundColor DarkGray
                        }
                    }
                    # Only now that the native build is in place: if the native install had
                    # failed, removing the npm copy first would leave the user with neither.
                    $null = Remove-NpmDuplicate $npmName $nativeCmd $nativeDir
                } else {
                    Write-Host "  -> $($pkg.Name) [FAILED] native installer (log: $nativeLog)" -ForegroundColor Red
                    $failedPkgs += "$($pkg.Name) (native installer)"
                    # 실제 원인 줄을 화면에도 노출한다.
                    $keyLines = @((Get-Content $nativeLog -ErrorAction SilentlyContinue) |
                        Where-Object { $_ -match 'symlink|Refusing|tar|Cannot extract|throw|Error|Exception|ETIMEDOUT|ENOTFOUND|denied|SHA256|checksum' } |
                        Select-Object -Last 8)
                    foreach ($l in $keyLines) { Write-Host "    $($l.Trim())" -ForegroundColor DarkGray }
                }
            } catch {
                Write-Host "  -> $($pkg.Name) [FAILED] native installer: $($_.Exception.Message)" -ForegroundColor Red
                "EXCEPTION: $($_.Exception.Message)" | Out-File -FilePath $nativeLog -Encoding utf8 -Append
                $failedPkgs += "$($pkg.Name) (native installer)"
            } finally {
                Remove-TempPath $tmp
                $env:TEMP = $savedTemp; $env:TMP = $savedTmp
                if ($null -eq $savedCodexHome) { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue } else { $env:CODEX_HOME = $savedCodexHome }
                if ($null -eq $savedNI) { Remove-Item Env:CODEX_NON_INTERACTIVE -ErrorAction SilentlyContinue } else { $env:CODEX_NON_INTERACTIVE = $savedNI }
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

# ── Old Gemini CLI: ask before removing ───────────────────
# Older versions of this script installed @google/gemini-cli with npm. Google stopped
# serving it for free/Pro/Ultra accounts on 2026-06-18, and this script no longer
# updates it, so it is left frozen and (for personal accounts) unusable.
#   * Ask first, default No: paid-API-key users may still rely on it.
#   * Non-interactive / dry-run: never prompt, only print the manual command.
#   * Only the npm package is removed. ~\.gemini is NEVER touched: Antigravity CLI
#     keeps using it (GEMINI.md, MCP config, skills), and `agy plugin import gemini`
#     reads the old extensions from there, so it still works after the uninstall.
$geminiNpm = $null
if (-not $DryRun) { $geminiNpm = Get-Command npm.cmd -ErrorAction SilentlyContinue }
$geminiVer = $null
if ($geminiNpm) {
    $gLs = & $geminiNpm.Source ls -g '@google/gemini-cli' --depth=0 --json 2>$null | Out-String
    if ($gLs) {
        try {
            $gDeps = ($gLs | ConvertFrom-Json).dependencies
            if ($gDeps -and $gDeps.PSObject.Properties['@google/gemini-cli']) { $geminiVer = $gDeps.'@google/gemini-cli'.version }
        } catch {}
    }
}
if ($geminiVer) {
    $agyBin = Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe'
    Write-Host ""
    Write-Host "Old Gemini CLI found (npm, v$geminiVer)." -ForegroundColor Yellow
    Write-Host "  Google stopped serving it for free/Pro/Ultra accounts on 2026-06-18 (paid API keys still work)." -ForegroundColor DarkGray
    Write-Host "  Antigravity CLI (agy) replaces it. Your settings in ~\.gemini are kept either way." -ForegroundColor DarkGray
    $removeGemini = $false
    if ($NonInteractive) {
        Write-Host "  To remove it:  npm uninstall -g @google/gemini-cli" -ForegroundColor DarkGray
    } else {
        $gAns = Read-Host "  예전 Gemini CLI 를 삭제할까요? 유료 API 키로 계속 쓰신다면 N [y/N]"
        $removeGemini = ($gAns -match '^(y|yes)$')
        if (-not $removeGemini) { Write-Host "  Kept. Remove later with:  npm uninstall -g @google/gemini-cli" -ForegroundColor DarkGray }
    }
    if ($removeGemini) {
        $gOut = & $geminiNpm.Source uninstall -g '@google/gemini-cli' 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  -> Gemini CLI removed (~\.gemini kept)." -ForegroundColor Green
            if (Test-Path $agyBin) {
                Write-Host "  Gemini extensions you used can be moved over with:  agy plugin import gemini" -ForegroundColor DarkGray
            }
        } else {
            # Optional cleanup: report it, but never count it as an install failure.
            Write-Host "  -> could not remove Gemini CLI (npm exit $LASTEXITCODE). Try:  npm uninstall -g @google/gemini-cli" -ForegroundColor Yellow
            $gLines = @($gOut -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 4)
            foreach ($l in $gLines) { Write-Host "    $($l.Trim())" -ForegroundColor DarkGray }
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
# Run in a child process to avoid the -ExecutionPolicy Bypass override from the parent shell.
# -NoProfile: without it the child loads the user's whole profile (zoxide, PSReadLine, ...)
# just to change one setting - several seconds, and it printed "PowerShell loaded in Nms"
# in the middle of the install output.
if (-not $DryRun) {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        pwsh -NoProfile -Command "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" 2>$null
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
    # pwsh_profile_cache.ps1 is the current single cache; the other two are the older
    # two-file layout, removed so they do not linger.
    Remove-TempPath "$env:TEMP\pwsh_profile_cache.ps1", "$env:TEMP\pwsh_tools_cache.ps1", "$env:TEMP\zoxide_init_cache.ps1"
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
            Remove-TempPath $tmpDir -Recurse
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
            # WinPS 5.1 의 ConvertFrom-Json 은 // 주석이 있는 JSON 에서 예외를 던진다(PS7 은 관대).
            # Windows Terminal 기본 settings.json 은 // 줄 주석을 포함하므로, 파싱 전에 줄 시작
            # 주석만 제거한다 ("https://" 같은 값 내부의 // 는 줄 시작이 아니라 영향 없음).
            $jsonLines = @(Get-Content $p) -notmatch '^\s*//'
            $cfg = ($jsonLines -join "`n") | ConvertFrom-Json -ErrorAction Stop
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
    # 전부 성공했을 때만 star 제안 (mac/linux 와 동등). 로그인+미star 일 때만 묻는다.
    $ghStar = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghStar -and -not $NonInteractive) {
        & $ghStar.Source auth status 2>$null
        if ($LASTEXITCODE -eq 0) {
            & $ghStar.Source api user/starred/hd0126/dev-setup 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host ""
                $starAns = Read-Host "이 스크립트가 도움이 됐다면 GitHub star로 응원해주세요! 지금 누를까요? [y/N]"
                if ($starAns -match '^(y|yes)$') {
                    & $ghStar.Source api -X PUT user/starred/hd0126/dev-setup 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) { Write-Host "  Star 감사합니다!" -ForegroundColor Green }
                    else { Write-Host "  star 실패 — https://github.com/hd0126/dev-setup 에서 직접 눌러주세요." -ForegroundColor DarkGray }
                }
            }
        } else {
            Write-Host "도움이 됐다면 star: https://github.com/hd0126/dev-setup" -ForegroundColor DarkGray
        }
    }
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

    # ── 진단 정보 수집 (원인 파악에 필요한 맥락) ───────────────
    # 이전 리포트는 정보가 부족해 진짜 원인(예: 프로필 경로가 심볼릭 링크라 tar 가
    # "Cannot extract through symlink" 로 압축 해제를 거부) 파악이 어려웠다.
    # 아래 항목을 자동으로 채워 재현·진단이 가능하게 한다.
    $diagArch = try { [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture } catch { $env:PROCESSOR_ARCHITECTURE }
    $diagWinget = try { (winget --version 2>$null | Out-String).Trim() } catch { '' }
    if (-not $diagWinget) { $diagWinget = 'n/a' }

    # 경로가 심볼릭 링크/정션이면 대상까지 표기한다 (codex tar 실패의 핵심 단서).
    function Get-LinkInfo([string]$p) {
        try {
            $it = Get-Item $p -Force -ErrorAction Stop
            if ($it.Target) { return "$p  ->  $($it.Target)  [reparse point]" }
            return "$p  [normal]"
        } catch { return "$p  [n/a]" }
    }

    # 주요 도구의 실제 실행 경로 (native vs npm 혼재 여부까지 드러난다).
    function Get-CmdInfo([string]$n) {
        $c = Get-Command $n -ErrorAction SilentlyContinue
        if ($c) { return "- ${n}: $($c.Source)" } else { return "- ${n}: (not found)" }
    }
    $toolLines = @('node','npm','git','codex','claude','agy','winget','python','uv') | ForEach-Object { Get-CmdInfo $_ }

    $reportBody = @"
## 환경 (Environment)
- OS: Windows $([Environment]::OSVersion.Version)
- PowerShell: $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))
- Architecture: $diagArch
- winget: $diagWinget

## 경로 진단 (Path diagnostics)
- USERPROFILE: $(Get-LinkInfo $env:USERPROFILE)
- LOCALAPPDATA: $(Get-LinkInfo $env:LOCALAPPDATA)
- TEMP: $(Get-LinkInfo $env:TEMP)

## 감지된 도구 (Detected tools)
$($toolLines -join "`n")

## 실패 항목 (Failed items)
$(( $failedPkgs | ForEach-Object { "- $_" } ) -join "`n")

## 로그 (Logs)
- $env:TEMP\omc-install-*.log

## 추가 상황 (Notes)
<!-- 무엇을 하다 생긴 문제인지 적어주세요 -->
"@

    # gh 로 제출하는 전체 본문에는 로그 꼬리(각 20줄)까지 접이식(details)으로 붙인다.
    # (브라우저 URL 은 길이 제한이 있어 $reportBody 엔 로그 경로만 남긴다.)
    $fence = '```'
    $logTails = ''
    foreach ($lf in (Get-ChildItem "$env:TEMP\omc-install-*.log" -ErrorAction SilentlyContinue)) {
        $tail = (Get-Content $lf.FullName -Tail 20 -ErrorAction SilentlyContinue) -join "`n"
        $logTails += "`n<details><summary>$($lf.Name)</summary>`n`n$fence`n$tail`n$fence`n</details>`n"
    }
    $reportBodyFull = if ($logTails) { $reportBody + "`n## 상세 로그 (Log details)`n" + $logTails } else { $reportBody }
    $issueUrl = "https://github.com/hd0126/dev-setup/issues/new?title=$([uri]::EscapeDataString($reportTitle))&body=$([uri]::EscapeDataString($reportBody))"

    Write-Host "문제를 알려주세요 (초보 환영):" -ForegroundColor Cyan
    Write-Host "  아래 링크를 열면 OS·에러·로그 경로가 자동으로 채워집니다 (Submit만 누르면 끝):" -ForegroundColor DarkGray
    Write-Host "  $issueUrl" -ForegroundColor Cyan
    Write-Host "  (로그 파일: $env:TEMP\omc-install-*.log)" -ForegroundColor DarkGray

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($gh -and -not $NonInteractive) {
        Write-Host ""
        $ans = Read-Host "  gh로 지금 바로 이슈를 생성할까요? [y/N]"
        if ($ans -match '^(y|yes)$') {
            # 로그인 여부를 먼저 확인하고, 안 돼 있으면 브라우저 로그인을 즉석 안내 (mac/linux 와 동등).
            & $gh.Source auth status 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  GitHub 로그인이 필요합니다 — 브라우저 안내를 따라주세요 (무료 계정이면 충분)." -ForegroundColor DarkGray
                & $gh.Source auth login --hostname github.com --web
            }
            & $gh.Source auth status 2>$null
            if ($LASTEXITCODE -eq 0) {
                $tmpBody = Join-Path $env:TEMP "devsetup-issue-body.md"
                $reportBodyFull | Out-File -FilePath $tmpBody -Encoding utf8
                & $gh.Source issue create --repo hd0126/dev-setup --title $reportTitle --body-file $tmpBody
                if ($LASTEXITCODE -eq 0) { Write-Host "  이슈가 생성되었습니다. 감사합니다!" -ForegroundColor Green }
                else { Write-Host "  gh 제출 실패 — 위 링크로 직접 열어주세요 (클릭 -> Submit)." -ForegroundColor DarkGray }
                Remove-TempPath $tmpBody
            } else {
                Write-Host "  로그인이 완료되지 않았습니다 — 위 링크로 직접 열어주세요 (클릭 -> Submit)." -ForegroundColor DarkGray
            }
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
    Write-Host "  npm install -g oh-my-codex" -ForegroundColor DarkGray
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

# 실패 항목이 있으면 비정상 종료 — CI·프로비저닝 도구가 실패를 감지할 수 있도록.
# irm | iex 경로는 exit가 사용자 터미널 세션을 닫아버리므로(위 dry-run 분기와 동일한 이유)
# 파일 실행일 때만 종료 코드로 전달하고, iex는 위에 출력된 실패 목록으로 갈음한다.
if ($failedPkgs.Count -gt 0 -and $RunAsFile) { exit 1 }
