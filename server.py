#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
mypac —— 轻量级 PAC (Proxy Auto-Config) 文件服务

功能：
  - 在指定端口提供 PAC 下载（默认 10390）
  - 支持任意路径访问，直接 http://ip:port 即可
  - 根据客户端来源动态生成代理地址（本机→127.0.0.1，局域网→配置值）
  - 带 CORS 头，方便网页端调试
  - 访问日志按天滚动，保存到 .cache/logs/，默认保留 7 天

配置：
  读取同目录下的 .env 文件（手动解析，零依赖）：
    PAC_PORT=10390              # PAC 服务监听端口
    PROXY_TARGET=127.0.0.1:7890  # 上游代理 IP:PORT
    LOG_RETAIN_DAYS=7           # 日志保留天数

用法：
  python3 server.py

无需任何第三方依赖，仅使用 Python 标准库。
"""

import os
import sys
import socket
import logging
from logging.handlers import TimedRotatingFileHandler
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


# ============================================================
#  .env 解析（零依赖手写，避免引入 python-dotenv）
# ============================================================
def parse_env(env_path):
    """解析简单 KEY=VALUE 格式的 .env 文件，返回 dict。"""
    cfg = {}
    if not os.path.isfile(env_path):
        return cfg
    with open(env_path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if " #" in line:
                line = line.split(" #")[0].strip()
            if "=" not in line:
                continue
            key, _, val = line.partition("=")
            key = key.strip()
            val = val.strip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
                val = val[1:-1]
            cfg[key] = val
    return cfg


# ============================================================
#  加载配置
# ============================================================
HERE = os.path.dirname(os.path.abspath(__file__))
ENV_FILE = os.path.join(HERE, ".env")
PAC_FILE = os.path.join(HERE, "proxy.pac")
LOG_DIR = os.path.join(HERE, ".cache", "logs")

_env = parse_env(ENV_FILE)

# 注意：用专用变量名，绝不读 os.environ['PORT']（Hermes 环境里 PORT=8648 会污染）
PAC_PORT = int(_env.get("PAC_PORT", "10390"))
PROXY_TARGET = _env.get("PROXY_TARGET", "127.0.0.1:7890")
LOG_RETAIN_DAYS = int(_env.get("LOG_RETAIN_DAYS", "7"))
HOST = "0.0.0.0"

# 本机访问时用的代理地址（把配置的 IP 降级为 127.0.0.1，走环回更快）
LOCAL_PROXY_TARGET = "127.0.0.1:" + PROXY_TARGET.rsplit(":", 1)[-1] if ":" in PROXY_TARGET else "127.0.0.1:7890"


# ============================================================
#  日志（按天滚动，保留 N 天）
# ============================================================
def _setup_logging():
    os.makedirs(LOG_DIR, exist_ok=True)
    fmt = logging.Formatter("%(asctime)s %(levelname)-5s %(message)s", datefmt="%Y-%m-%d %H:%M:%S")

    file_h = TimedRotatingFileHandler(
        os.path.join(LOG_DIR, "mypac.log"),
        when="midnight",
        interval=1,
        backupCount=LOG_RETAIN_DAYS,
        encoding="utf-8",
    )
    file_h.suffix = "%Y-%m-%d"
    file_h.setFormatter(fmt)

    console_h = logging.StreamHandler()
    console_h.setFormatter(fmt)

    logging.basicConfig(level=logging.INFO, handlers=[file_h, console_h])


_setup_logging()
log = logging.getLogger("mypac")


# ============================================================
#  加载 PAC 模板
# ============================================================
def load_pac_template():
    with open(PAC_FILE, "r", encoding="utf-8") as f:
        return f.read()


# ============================================================
#  HTTP Server（支持快速重启）
# ============================================================
class ReusableHTTPServer(ThreadingHTTPServer):
    def server_bind(self):
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if hasattr(socket, "SO_REUSEPORT"):
            try:
                self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
            except (AttributeError, OSError):
                pass
        super().server_bind()


# ============================================================
#  HTTP Handler
# ============================================================
class PacHandler(BaseHTTPRequestHandler):
    # 关键：必须用 HTTP/1.1。默认的 HTTP/1.0 会导致 Windows WinHTTP/部分浏览器
    # 的 PAC 解析器行为异常（无 keep-alive、连接提前关闭）。
    protocol_version = "HTTP/1.1"

    server_version = "mypac/1.0"

    def _send(self, code, body=b"", ctype="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        # PAC 文件不应被缓存，否则客户端拿到的旧代理地址无法更新
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        try:
            pac_tpl = load_pac_template()
        except FileNotFoundError:
            self._send(404, b"proxy.pac not found\n", "text/plain")
            return

        client_ip = self.client_address[0]

        # 本机访问降级为 127.0.0.1，局域网设备用配置的 PROXY_TARGET
        if client_ip.startswith("127."):
            proxy_addr = LOCAL_PROXY_TARGET
        else:
            proxy_addr = PROXY_TARGET

        pac = pac_tpl.replace("{{PROXY_TARGET}}", proxy_addr)
        self._send(200, pac.encode("utf-8"), "application/x-ns-proxy-autoconfig")
        log.info("%s 200 PAC (%db) proxy=%s %s", client_ip, len(pac), proxy_addr, self.path)

    def log_message(self, *args, **kwargs):
        pass


# ============================================================
#  辅助函数
# ============================================================
def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return None


# ============================================================
#  主函数
# ============================================================
def main():
    log.info("配置来源: %s", ENV_FILE if os.path.isfile(ENV_FILE) else "(无 .env，使用默认值)")
    log.info("  PAC_PORT        = %d", PAC_PORT)
    log.info("  PROXY_TARGET    = %s", PROXY_TARGET)
    log.info("  LOG_RETAIN_DAYS = %d", LOG_RETAIN_DAYS)

    try:
        pac_tpl = load_pac_template()
        log.info("PAC 模板加载成功 (%d 字节)", len(pac_tpl))
    except FileNotFoundError:
        log.error("找不到 proxy.pac: %s", PAC_FILE)
        sys.exit(1)

    try:
        srv = ReusableHTTPServer((HOST, PAC_PORT), PacHandler)
    except OSError as e:
        log.error("无法绑定 %s:%d → %s", HOST, PAC_PORT, e)
        log.error("如端口被占用: lsof -nP -iTCP:%d -sTCP:LISTEN", PAC_PORT)
        sys.exit(1)

    local_ip = get_local_ip()
    log.info("🚀 mypac 服务已启动")
    log.info("   本机访问 :  http://127.0.0.1:%d", PAC_PORT)
    if local_ip:
        log.info("   局域网访问:  http://%s:%d", local_ip, PAC_PORT)
    log.info("   本机代理 :  %s", LOCAL_PROXY_TARGET)
    log.info("   局域网代理:  %s", PROXY_TARGET)
    log.info("   日志目录 :  %s (保留 %d 天)", LOG_DIR, LOG_RETAIN_DAYS)
    log.info("   监听 %s:%d  (Ctrl+C 退出)", HOST, PAC_PORT)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        log.info("收到退出信号，关闭服务…")
        srv.shutdown()


if __name__ == "__main__":
    main()
