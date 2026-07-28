#!/usr/bin/env bash
# ============================================================
#  mypac 服务管理脚本 (macOS / Linux)
#  默认操作：重启（先按端口关闭旧进程，再后台启动新实例）
#
#  用法：
#    ./run.sh             重启（默认）
#    ./run.sh restart     重启
#    ./run.sh start       后台启动（不关旧进程）
#    ./run.sh stop        停止
#    ./run.sh status      查看状态
# ============================================================

set -u  # 注意：不用 set -e，否则 lsof 无结果(exit 1) 会让脚本直接挂掉

# ---------- 从 .env 读取端口（脚本仅用于进程查找/提示） ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_PY="$SCRIPT_DIR/server.py"
PYTHON_BIN="${PYTHON_BIN:-python3}"
PORT="10390"  # 默认值，优先用 .env 里的
HOST="0.0.0.0"
if [ -f "$SCRIPT_DIR/.env" ]; then
    # 简单提取 PAC_PORT=xxx
    _env_port="$(grep -E '^\s*PAC_PORT\s*=' "$SCRIPT_DIR/.env" 2>/dev/null | head -1 | sed -E 's/^\s*PAC_PORT\s*=\s*//; s/^["'"'"']//; s/["'"'"']$//; s/\s*#.*$//')"
    [ -n "$_env_port" ] && PORT="$_env_port"
fi

# ---------- 定位 python ----------
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo "[错误] 未找到 $PYTHON_BIN，请确认已安装 Python 3 并加入 PATH。"
    exit 1
fi

# ---------- 动作参数 ----------
ACTION="${1:-restart}"
case "$ACTION" in
    start|stop|restart|status) : ;;
    -h|--help|help)
        cat <<EOF
mypac 服务管理脚本
用法:
  ./run.sh             重启（默认：先停后启）
  ./run.sh restart     重启
  ./run.sh start       后台启动
  ./run.sh stop        停止
  ./run.sh status      查看状态
EOF
        exit 0 ;;
    *)
        echo "[错误] 未知参数: $ACTION  (可用: start|stop|restart|status)"
        exit 1 ;;
esac

# ---------- 子函数：查占用 PORT 的确切 PID ----------
# lsof 找不到进程时返回 exit 1，这里用 || true 兜底，避免误触发退出
find_pid() {
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $2}' | head -1 || true
}

# ---------- 子函数：停止 ----------
do_stop() {
    echo "=== 停止 mypac ==="
    local pid
    pid="$(find_pid)"
    if [ -z "$pid" ]; then
        echo "  服务未运行，无需操作。"
    else
        echo "  正在终止 PID=$pid ..."
        kill "$pid" 2>/dev/null || true
        # 等待端口释放（最多 5 秒）
        local i
        for i in 1 2 3 4 5; do
            sleep 1
            [ -z "$(find_pid)" ] && break
        done
        pid="$(find_pid)"
        if [ -z "$pid" ]; then
            echo "  [√] 已停止"
        else
            echo "  [!] 端口 $PORT 仍被占用 PID=$pid，请手动检查: lsof -nP -iTCP:$PORT"
        fi
    fi
    echo
}

# ---------- 子函数：后台启动 ----------
do_start() {
    echo "=== 启动 mypac ==="
    local pid
    pid="$(find_pid)"
    if [ -n "$pid" ]; then
        echo "  [!] 端口 $PORT 已被占用（PID=$pid）。请先 stop 或 restart。"
        echo
        return 0
    fi
    if [ ! -f "$SERVER_PY" ]; then
        echo "  [错误] 找不到 server.py: $SERVER_PY"
        return 1
    fi
    echo "  Python  : $PYTHON_BIN"
    echo "  脚本    : $SERVER_PY"
    echo "  监听    : $HOST:$PORT"
    echo "  日志    : $SCRIPT_DIR/.cache/logs/ (按天滚动，保留 7 天)"
    # 后台启动；日志由 server.py 内部写入 .cache/logs/mypac.log
    nohup "$PYTHON_BIN" "$SERVER_PY" >/dev/null 2>&1 &
    # 给进程时间绑定端口
    sleep 2
    pid="$(find_pid)"
    if [ -z "$pid" ]; then
        echo "  [!] 启动后未检测到监听，可能启动失败。最近日志:"
        tail -n 10 "$SCRIPT_DIR/.cache/logs/mypac.log" 2>/dev/null || true
    else
        echo
        echo "  [√] 启动成功  PID=$pid"
        echo "  本机访问 : http://127.0.0.1:$PORT"
    fi
    echo
}

# ---------- 子函数：状态 ----------
do_status() {
    echo "=== mypac 状态检查 ==="
    local pid
    pid="$(find_pid)"
    if [ -z "$pid" ]; then
        echo "  [ ] 服务未运行"
    else
        echo "  [√] 服务运行中  PID=$pid  端口=$PORT"
    fi
    echo
}

# ---------- 分发 ----------
case "$ACTION" in
    status) do_status ;;
    stop)   do_stop ;;
    start)  do_start ;;
    restart) do_stop; do_start ;;
esac
