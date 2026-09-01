param(
  [string]$InstanceId = "i-bp16w2dei36gapux2ew9",
  [string]$Region = "cn-hangzhou",
  [string]$MoxxRoot = "/opt/moxx",
  [switch]$SkipLocalChecks,
  [switch]$NoConfirm
)

$ErrorActionPreference = "Stop"

function Step($Message) {
  Write-Host ""
  Write-Host "==> $Message" -ForegroundColor Cyan
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$workbenchDir = Join-Path $env:LOCALAPPDATA "Programs\workbench"
if (Test-Path -LiteralPath $workbenchDir) {
  $env:PATH = "$workbenchDir;$env:PATH"
}

if (-not (Get-Command workbench -ErrorAction SilentlyContinue)) {
  throw "未找到 workbench CLI。请先安装 Workbench CLI。"
}

Step "确认 Workbench 配置与目标 ECS"
workbench config list
$instancesJson = workbench list ecs --region $Region --output json
$instances = $instancesJson | ConvertFrom-Json
$match = @($instances.instances | Where-Object { $_.instance_id -eq $InstanceId })
if ($match.Count -eq 0) {
  throw "未在 $Region 找到 ECS 实例 $InstanceId。"
}
Write-Host ("目标实例：{0} / {1} / {2}" -f $match[0].instance_name, $match[0].status, $match[0].public_ip)

if (-not $NoConfirm) {
  Write-Host ""
  Write-Host "将发布到生产 ECS：$InstanceId ($Region)，生产目录：$MoxxRoot" -ForegroundColor Yellow
  Write-Host "发布会上传新代码包，远端会备份数据库，随后停止并重启 moxx-api / moxx-web。"
  $answer = Read-Host "确认继续？输入 DEPLOY"
  if ($answer -ne "DEPLOY") {
    Write-Host "已取消发布。"
    exit 0
  }
}

if (-not $SkipLocalChecks) {
  Step "运行本地后端测试"
  npm run test:api

  Step "运行前端类型检查"
  npm run typecheck:web
}

Step "生成生产部署包"
bash scripts/make-deploy-package.sh
$packagePath = Join-Path $repoRoot "moxx-deploy.tar.gz"
if (-not (Test-Path -LiteralPath $packagePath)) {
  throw "未生成部署包：$packagePath"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$remotePackage = "$MoxxRoot/incoming/moxx-deploy-$timestamp.tar.gz"
$remoteScript = "/tmp/moxx-remote-update-$timestamp.sh"

Step "准备远端 incoming 目录"
workbench exec --instance-id $InstanceId --timeout 30 --command "mkdir -p '$MoxxRoot/incoming' && df -h '$MoxxRoot'"

Step "上传部署包"
workbench upload $packagePath $remotePackage --instance-id $InstanceId

Step "上传远端更新脚本"
workbench upload (Join-Path $repoRoot "scripts\remote-update-production.sh") $remoteScript --instance-id $InstanceId

Step "执行远端安全更新"
$remoteCommand = "chmod +x '$remoteScript' && MOXX_ROOT='$MoxxRoot' PACKAGE='$remotePackage' bash '$remoteScript'"
workbench exec --instance-id $InstanceId --timeout 1800 --command $remoteCommand

Step "发布后健康检查"
workbench exec --instance-id $InstanceId --timeout 60 --command "systemctl is-active moxx-api; systemctl is-active moxx-web; systemctl is-active nginx; curl -fsS http://127.0.0.1:8010/healthz"

Write-Host ""
Write-Host "生产发布完成。" -ForegroundColor Green
