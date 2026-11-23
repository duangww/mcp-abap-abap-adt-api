# 把 GitHub 的 main 快进进来，再把 local 分支上的补丁接回去，然后安装依赖并编译。
# 工作区有未提交改动、rebase 冲突、安装或编译失败时退出，不继续后面的步骤。
# 日志：logs\update-local.log
$ErrorActionPreference = 'Stop'
$repo = 'D:\AI\ABAP_MCP\mcp-abap-abap-adt-api'
Set-Location $repo

$logDir = Join-Path $repo 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'update-local.log'

function Write-Log([string]$Message) {
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
  Add-Content -Path $log -Value $line -Encoding utf8
  Write-Host $line
}

function Invoke-Git([string[]]$GitArgs) {
  & git @GitArgs
  if ($LASTEXITCODE -ne 0) {
    throw "git $($GitArgs -join ' ') 失败，退出码 $LASTEXITCODE"
  }
}

try {
  $branch = (& git rev-parse --abbrev-ref HEAD).Trim()
  if ($LASTEXITCODE -ne 0) { throw '无法识别当前分支' }
  if ($branch -ne 'local') {
    throw "当前分支是 $branch。这个脚本只在 local 上运行。"
  }

  $dirty = & git status --porcelain
  if ($LASTEXITCODE -ne 0) { throw 'git status 失败' }
  if ($dirty) {
    throw "工作区有未提交改动，先提交后再更新。`n$($dirty -join "`n")"
  }

  Write-Log '开始 fetch origin'
  Invoke-Git @('fetch', 'origin')

  Write-Log '开始 rebase origin/main'
  & git rebase origin/main
  if ($LASTEXITCODE -ne 0) {
    Write-Log 'rebase 未完成。处理冲突后执行 git rebase --continue；要放弃这次更新则执行 git rebase --abort'
    exit 1
  }

  Write-Log '开始 npm install'
  & npm install
  if ($LASTEXITCODE -ne 0) { throw "npm install 失败，退出码 $LASTEXITCODE" }

  Write-Log '开始 npm run build'
  & npm run build
  if ($LASTEXITCODE -ne 0) { throw "npm run build 失败，退出码 $LASTEXITCODE" }

  Write-Log '完成。在 Cursor 里重新加载 mcp-abap-dev 后才会用到新的 dist\index.js'
  exit 0
}
catch {
  Write-Log $_.Exception.Message
  exit 1
}
