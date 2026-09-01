#!/usr/bin/env bash
# Production update sequence for /opt/moxx.
# Intended to be invoked by scripts/deploy-production.ps1 through Workbench CLI.
set -euo pipefail

MOXX="${MOXX_ROOT:-/opt/moxx}"
PACKAGE="${PACKAGE:-}"
APP_USER="${APP_USER:-moxx}"
API="$MOXX/apps/api"
WEB="$MOXX/apps/web"
INCOMING="$MOXX/incoming"
CURRENT_TAR="$INCOMING/moxx-deploy.tar.gz"
PREV_TAR="$INCOMING/moxx-deploy.prev.tar.gz"
DB="$API/personal_writing_agent_mvp1.db"

TS="$(date +%Y%m%d_%H%M%S)"
LOG="$MOXX/update-$TS.log"
DB_BACKUP="/root/moxx-db-backup-$TS.db"
ENV_BACKUP="/root/moxx-env-backup-$TS.local"

exec > >(tee -a "$LOG") 2>&1

on_fail() {
  echo "[FAIL] 更新失败，开始回滚（日志：$LOG）"
  systemctl stop moxx-api moxx-web 2>/dev/null || true

  if [ -f "$DB_BACKUP" ]; then
    cp "$DB_BACKUP" "$DB"
    echo "[ROLLBACK] 已恢复数据库备份 -> $DB"
  fi

  if [ -f "$ENV_BACKUP" ]; then
    cp "$ENV_BACKUP" "$API/.env.local"
    echo "[ROLLBACK] 已恢复 API 环境文件 -> $API/.env.local"
  fi

  if [ -f "$PREV_TAR" ]; then
    tar -xzf "$PREV_TAR" -C "$MOXX"
    echo "[ROLLBACK] 已重新解压上一份代码包"
  fi

  chown -R "$APP_USER:$APP_USER" "$API" "$WEB" "$MOXX/scripts" 2>/dev/null || true
  chmod 755 "$API" 2>/dev/null || true
  systemctl start moxx-api moxx-web 2>/dev/null || true
  echo "[FAIL] 回滚完成，请人工确认服务状态。"
}
trap on_fail ERR

echo "===== 开始生产更新 $TS ====="
echo "[pre] MOXX=$MOXX"
echo "[pre] PACKAGE=$PACKAGE"

[ -d "$MOXX" ] || { echo "[pre] 生产目录不存在：$MOXX"; exit 1; }
[ -n "$PACKAGE" ] || { echo "[pre] 未传入 PACKAGE"; exit 1; }
[ -f "$PACKAGE" ] || { echo "[pre] 更新包不存在：$PACKAGE"; exit 1; }
[ -d "$API" ] || { echo "[pre] API 目录不存在：$API"; exit 1; }
[ -d "$WEB" ] || { echo "[pre] WEB 目录不存在：$WEB"; exit 1; }

AVAIL=$(df -m "$MOXX" | awk 'NR==2{print $4}')
if [ "${AVAIL:-0}" -lt 700 ]; then
  echo "[pre] 磁盘可用空间不足 700MB（当前 ${AVAIL}MB），中止"
  exit 1
fi

if ! tar -tzf "$PACKAGE" >/dev/null; then
  echo "[pre] 更新包不是有效 tar.gz，或已损坏"
  exit 1
fi

mkdir -p "$INCOMING"
if [ -f "$CURRENT_TAR" ]; then
  cp "$CURRENT_TAR" "$PREV_TAR"
  echo "[pre] 已保存上一份部署包 -> $PREV_TAR"
fi
cp "$PACKAGE" "$CURRENT_TAR"

echo "[1/6] 备份数据库与环境文件"
[ -f "$DB" ] || { echo "[pre] 数据库不存在：$DB"; exit 1; }
cp "$DB" "$DB_BACKUP"
[ -f "$API/.env.local" ] && cp "$API/.env.local" "$ENV_BACKUP"

echo "[2/6] 停止应用服务"
systemctl stop moxx-api moxx-web || true
sleep 2

echo "[3/6] 覆盖解压代码（保留包外 db / .env.local / .venv / .next）"
tar -xzf "$CURRENT_TAR" -C "$MOXX"
chown -R "$APP_USER:$APP_USER" "$API" "$WEB" "$MOXX/scripts" 2>/dev/null || true
chmod 755 "$API" 2>/dev/null || true

echo "[4/6] 执行数据库迁移"
export DATABASE_URL="sqlite+pysqlite:///$DB"
cd "$API"
.venv/bin/python -m app.core.migrate

echo "[5/6] 安装依赖并构建前端"
cd "$API"
.venv/bin/pip install -r requirements.txt || true
cd "$MOXX"
npm install
NEXT_PUBLIC_API_BASE_URL=/api npm --workspace apps/web run build

if grep -rlq "NEXT_PUBLIC_API_BASE_URL" "$WEB/.next/static/chunks/" --include='*.js' 2>/dev/null; then
  echo "[FAIL] 前端构建产物残留 NEXT_PUBLIC_API_BASE_URL，停止发布"
  exit 1
fi
if grep -rlq ":8010" "$WEB/.next/static/chunks/" --include='*.js' 2>/dev/null; then
  echo "[FAIL] 前端构建产物残留 :8010 直连，停止发布"
  exit 1
fi
echo "[ok] 前端构建产物检查通过"

chown -R "$APP_USER:$APP_USER" "$API" "$WEB" "$MOXX/scripts" 2>/dev/null || true
chmod 755 "$API" 2>/dev/null || true

echo "[6/6] 重启服务并健康检查"
systemctl daemon-reload
systemctl start moxx-api moxx-web
sleep 6
curl -fsS http://127.0.0.1:8010/healthz >/dev/null
systemctl is-active --quiet moxx-api
systemctl is-active --quiet moxx-web

if [ -f "$MOXX/deploy-manifest.json" ]; then
  echo "[ok] 当前部署 manifest:"
  cat "$MOXX/deploy-manifest.json"
fi

echo "===== 生产更新成功 $TS ====="
echo "日志：$LOG"
