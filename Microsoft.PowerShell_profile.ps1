# --- 0. Profile load timer ---
$profileStart = Get-Date

# --- 1. Claude Code shortcuts ---
function cc    { claude --dangerously-skip-permissions @args }
function ccc   { cc --continue @args }
function ccr   { cc --resume @args }
function which { Get-Command @args }
function touch { $args | ForEach-Object { if (Test-Path $_) { (Get-Item $_).LastWriteTime = Get-Date } else { New-Item $_ -ItemType File | Out-Null } } }

# --- 2. Conda lazy loading ---
function conda {
    Remove-Item Function:\conda -ErrorAction SilentlyContinue
    Write-Host "Initializing Conda..." -ForegroundColor Cyan
    Import-Module "$Env:_CONDA_ROOT\shell\condabin\Conda.psm1" -ArgumentList @{ChangePs1 = $True}
    conda @args
}

# --- 3. 도구 캐시: 설치 여부 + zoxide init 을 파일 하나에 ---
# 첫 줄에 이 프로필과 각 도구 exe 의 수정 시각을 적어 두고, 시작할 때마다 그 시각만
# 비교한다(Get-Command·zoxide.exe 실행 없이 파일 시각 몇 개 읽기). 프로필이 바뀌거나
# `winget upgrade zoxide` 등으로 exe 가 바뀌면 자동으로 다시 만든다 — 예전에는 캐시를
# 지우기 전까지 옛 zoxide init 을 계속 썼다. 캐시를 만든 뒤에 새로 설치한 도구는
# install.ps1 이 캐시를 지워 반영한다. 강제 재생성:
#   Remove-Item ([IO.Path]::GetFullPath("$env:TEMP\pwsh_profile_cache.ps1"))
$profileCache = "$env:TEMP\pwsh_profile_cache.ps1"
$_cacheSelf   = if ($PSCommandPath) { $PSCommandPath } else { $PROFILE }
$_cacheOk     = $false
# 수정 시각은 링크가 아니라 링크가 가리키는 실제 파일에서 읽는다 — 프로필을 dotfiles 레포로
# 심볼릭 링크했거나 도구가 WinGet\Links 같은 링크로 잡혀도, 실제 파일이 바뀌면 감지된다.
$_mtime = {
    param([string]$p)
    $fi = [IO.FileInfo]::new($p)
    try { $tgt = $fi.ResolveLinkTarget($true); if ($tgt) { $fi = [IO.FileInfo]::new($tgt.FullName) } } catch {}
    [string]$fi.LastWriteTimeUtc.Ticks
}
if (Test-Path -LiteralPath $profileCache) {
    try {
        $_r = [IO.StreamReader]::new($profileCache)
        try { $_head = $_r.ReadLine() } finally { $_r.Close() }
        $_fields  = @("$_head".TrimStart('#', ' ') -split "`t")
        $_cacheOk = ($_fields.Count -ge 2) -and ($_fields[0] -eq 'devsetup-cache 2') -and
                    ($_fields[1] -eq (& $_mtime $_cacheSelf))
        for ($_i = 2; $_cacheOk -and $_i -lt $_fields.Count; $_i++) {
            $_exe, $_ticks = $_fields[$_i] -split '\|', 2
            $_cacheOk = (Test-Path -LiteralPath $_exe) -and ((& $_mtime $_exe) -eq $_ticks)
        }
    } catch { $_cacheOk = $false }
}
if (-not $_cacheOk) {
    $_tools  = [ordered]@{ hasZoxide = 'zoxide'; hasFzf = 'fzf'; hasStarship = 'starship'; hasEza = 'eza'; hasFd = 'fd' }
    $_stamps = @(); $_body = @(); $_zExe = $null
    foreach ($_k in $_tools.Keys) {
        $_c = Get-Command $_tools[$_k] -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        $_body += "`$$_k = `$$(([bool]$_c).ToString().ToLower())"
        if ($_c) {
            $_stamps += "$($_c.Source)|$(& $_mtime $_c.Source)"
            if ($_k -eq 'hasZoxide') { $_zExe = $_c.Source }
        }
    }
    $_text = @((@('# devsetup-cache 2', (& $_mtime $_cacheSelf)) + $_stamps) -join "`t") + $_body
    if ($_zExe) { $_text += (& $_zExe init powershell --cmd z | Out-String) }
    # 임시 파일에 다 쓴 뒤 교체한다 — 터미널 여러 개가 동시에 열려도 반쯤 쓰인 캐시를 읽지 않게.
    $_tmpC = "$profileCache.$PID.tmp"
    try {
        Set-Content -LiteralPath $_tmpC -Value $_text -Encoding UTF8
        Move-Item -LiteralPath $_tmpC -Destination $profileCache -Force
    } catch {
        Remove-Item -LiteralPath $_tmpC -Force -ErrorAction Ignore
    }
}
if (Test-Path -LiteralPath $profileCache) { . $profileCache }
# -ErrorAction Ignore: SilentlyContinue 는 없는 변수마다 $Error 에 기록을 남긴다.
Remove-Variable _cacheSelf, _cacheOk, _mtime, _r, _head, _fields, _i, _exe, _ticks, _tools, _stamps, _body, _zExe, _k, _c, _text, _tmpC -ErrorAction Ignore

# --- 4. eza / fd (macOS·Linux 와 같은 별칭) ---
if ($hasEza) {
    function ll { eza -l @args }
    function la { eza -la @args }
    function lt { eza --tree @args }
}
if ($hasFd -and -not $env:FZF_DEFAULT_COMMAND) {
    # fzf 의 Ctrl+T 파일 검색을 fd 로 (.gitignore 존중, 숨김 파일 포함, .git 제외).
    # 직접 설정해 둔 FZF_DEFAULT_COMMAND 가 있으면 그대로 둔다.
    $env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --follow --exclude .git'
}

# --- 5. PSReadLine (ConsoleHost only) ---
if ($Host.Name -eq 'ConsoleHost') {
    # fzf 파이프를 오가는 한글 히스토리가 mojibake로 깨지지 않도록 콘솔을 UTF-8로.
    # (레거시 코드페이지 콘솔에서 fzf가 CP949로 주고받으면 선택 결과가 깨진다)
    try {
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        [Console]::InputEncoding  = [Text.Encoding]::UTF8
    } catch {}
    try {
        Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView
        Set-PSReadLineOption -Colors @{ InlinePrediction = '#8A8A8A' }
    } catch {}
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

    if ($hasFzf) {
        Set-PSReadLineKeyHandler -Key Ctrl+r -ScriptBlock {
            $line = $null; $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            $selected = Get-Content (Get-PSReadLineOption).HistorySavePath |
                        fzf --tac --no-sort --height 40% --layout reverse --border --query $line
            if ($selected) {
                [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
            }
        }
        Set-PSReadLineKeyHandler -Key Ctrl+t -ScriptBlock {
            $line = $null; $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            $selected = fzf --height 40% --layout reverse --border
            if ($selected) { [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected) }
        }
    }
}

# --- 5b. 순수 PowerShell 프롬프트 (외부 바이너리 없음 → V3 스캔 없음) ---
# junction 경로와 실제 경로 양쪽 모두 ~ 로 치환
$_homePatterns = @(
    [regex]::Escape($HOME)
    [regex]::Escape((Get-Item $HOME -ErrorAction SilentlyContinue).Target ?? $HOME)
) | Select-Object -Unique

function global:prompt {
    $ok = $?
    $path = $PWD.Path
    foreach ($pat in $_homePatterns) {
        if ($path -match "^$pat") { $path = '~' + $path.Substring($Matches[0].Length); break }
    }
    $parts = $path -split '[/\\]'
    $short = if ($parts.Count -gt 2) { '…\' + ($parts[-2..-1] -join '\') } else { $path }

    # Git 브랜치: .git/HEAD 직접 읽기 (git 바이너리 호출 없음)
    $branch = ''
    $gitHead = & {
        $d = $PWD.Path
        while ($d) {
            $g = Join-Path $d '.git'
            $f = Join-Path $g 'HEAD'
            if (Test-Path $f -PathType Leaf) { return $f }
            if (Test-Path $g -PathType Leaf) {
                # worktree/submodule: .git이 "gitdir: <경로>" 한 줄짜리 파일
                $gd = (Get-Content $g -Raw -ErrorAction SilentlyContinue) -replace '^gitdir:\s*', ''
                $gd = $gd.Trim()
                if ($gd) {
                    if (-not [IO.Path]::IsPathRooted($gd)) { $gd = Join-Path $d $gd }
                    $f2 = Join-Path $gd 'HEAD'
                    if (Test-Path $f2 -PathType Leaf) { return $f2 }
                }
                return
            }
            $p = Split-Path $d -Parent
            if ($p -eq $d) { break }
            $d = $p
        }
    }
    if ($gitHead) {
        $raw = Get-Content $gitHead -Raw -ErrorAction SilentlyContinue
        if ($raw -match 'ref: refs/heads/(.+)') { $branch = " on $($Matches[1].Trim())" }
        elseif ($raw) { $branch = " on $($raw.Trim().Substring(0, [math]::Min(7,$raw.Trim().Length)))" }
    }

    Write-Host ""
    Write-Host $short -NoNewline -ForegroundColor Cyan
    if ($branch) { Write-Host $branch -NoNewline -ForegroundColor Magenta }
    Write-Host ""
    if ($ok) { Write-Host '❯' -NoNewline -ForegroundColor Green }
    else      { Write-Host '❯' -NoNewline -ForegroundColor Red   }
    return ' '
}

# --- 6. SSH agent ---
$sshAgent = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($sshAgent -and $sshAgent.Status -eq 'Running') {
    ssh-add -l 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        # 키 파일명을 하드코딩하지 않고 .ssh 폴더에서 자동 탐색
        $sshKey = Get-ChildItem "$env:USERPROFILE\.ssh" -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -eq '' -and $_.Name -notmatch '\.pub$|known_hosts|config' } |
            Select-Object -First 1 -ExpandProperty FullName
        if ($sshKey) { ssh-add $sshKey 2>$null | Out-Null }
    }
}

# --- 7. Profile load time ---
$loadTime = ((Get-Date) - $profileStart).TotalMilliseconds
Write-Host "PowerShell loaded in $([math]::Round($loadTime))ms" -ForegroundColor DarkGray
