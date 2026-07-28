# ============================================================
#  mypac Dockerfile
#  轻量级 PAC 服务，基于 python:3.12-slim
# ============================================================
FROM python:3.12-slim

LABEL maintainer="mypac"
LABEL description="轻量级 PAC 代理自动配置服务"

# 设置时区（让按天滚动的日志在本地午夜切割）
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

WORKDIR /app

# 复制项目文件（server.py 仅依赖 Python 标准库，无需 requirements.txt）
COPY proxy.pac server.py ./

# .env 由 docker-compose 挂载或环境变量注入，这里不 COPY

EXPOSE 10390

# 健康检查：访问 PAC 端口
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:${PAC_PORT:-10390}/', timeout=3)" || exit 1

CMD ["python", "server.py"]
