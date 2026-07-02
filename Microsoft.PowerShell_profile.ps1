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

# --- 3. Tool availability cache (재생성: Remove-Item $env:TEMP\pwsh_tools_cache.ps1) ---
$toolsCache = "$env:TEMP\pwsh_tools_cache.ps1"
if (-not (Test-Path $toolsCache)) {
    $z = [bool](Get-Command zoxide   -ErrorAction SilentlyContinue)
    $f = [bool](Get-Command fzf      -ErrorAction SilentlyContinue)
    $s = [bool](Get-Command starship -ErrorAction SilentlyContinue)
    @(
        "`$hasZoxide   = `$$($z.ToString().ToLower())"
        "`$hasFzf      = `$$($f.ToString().ToLower())"
        "`$hasStarship = `$$($s.ToString().ToLower())"
    ) -join "`n" | Out-File $toolsCache -Encoding UTF8
}
. $toolsCache

# --- 4. zoxide (cached) ---
if ($hasZoxide) {
    $zoxideCache = "$env:TEMP\zoxide_init_cache.ps1"
    if (-not (Test-Path $zoxideCache)) {
        zoxide init powershell --cmd z | Out-File $zoxideCache -Encoding UTF8
    }
    . $zoxideCache
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
            $f = Join-Path $d '.git\HEAD'
            if (Test-Path $f -PathType Leaf) { return $f }
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
