# mypac —— 轻量级 PAC 自动代理服务

> 内网 IP 直连，其他流量走 `127.0.0.1:7890`
> 纯 Python 标准库实现，零依赖，启动即用。


> 🌐 **[在线宣传页](https://samge0.github.io/mypac/)** — 可视化了解功能特性与工作流程

## 🚀 快速开始

```bash
cd /Users/samge/PRO/other/mypac
python3 server.py
```

默认监听 `0.0.0.0:10390`，局域网内任何设备都能用。

启动后 PAC 地址（直接用 IP:端口访问，无需任何路径后缀）：

| 场景 | URL |
|------|-----|
| 本机     | `http://127.0.0.1:10390` |
| 局域网   | `http://<本机IP>:10390` |

## ⚙️ 客户端配置

### macOS 系统（全局）
1. 系统设置 → 网络 → Wi-Fi（或以太网）→ 详细信息 → 代理
2. 勾选 **自动代理配置 (PAC)**
3. URL 填：`http://127.0.0.1:10390`

### ClashX / Surge 等客户端
- 在「外部资源 / PAC」中填入上面的 URL
- 或浏览器插件 SwitchyOmega → auto switch → 填入 PAC URL

### 命令行（curl 测试）
```bash
# 查看 PAC 返回的策略内容
curl http://127.0.0.1:10390

# 让 curl 使用 PAC（需要 c-ares 支持，部分版本可用）
curl --pac http://127.0.0.1:10390 https://www.google.com
```

## 📐 代理规则

| 类型 | 示例 | 策略 |
|------|------|------|
| 本机主机名 | `nas` | DIRECT |
| localhost / 127.x | `127.0.0.1` | DIRECT |
| 内网域名后缀 | `*.local / *.lan / *.internal / *.corp / *.home` | DIRECT |
| 内网 IP（直接 IP 访问） | `10.x.x.x` / `172.16-31.x.x` / `192.168.x.x` | DIRECT |
| 其他所有 | `google.com` 等 | **PROXY 代理** |

> 💡 **设计原则**：采用**白名单制**（默认走代理，仅明确内网走直连），不依赖 `dnsResolve` 反查域名 IP。这样即使客户端 DNS 被污染（被墙域名解析到内网 IP），也不会误判为直连。

## ⚙️ 配置（.env 文件）

通过项目根目录的 `.env` 文件自定义端口和代理地址：

```bash
cp .env.example .env   # 首次使用，从模板创建
```

`.env` 内容：

```ini
PAC_PORT=10390                      # PAC 服务监听端口
PROXY_TARGET=127.0.0.1:7890    # 上游代理地址（IP:PORT）
```

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `PAC_PORT` | PAC 服务监听端口 | `10390` |
| `PROXY_TARGET` | 上游代理地址，局域网设备将通过此地址连接你的代理 | `127.0.0.1:7890` |
| `LOG_RETAIN_DAYS` | 日志保留天数（按天滚动，到期自动清理） | `7` |

**智能代理地址**：服务会根据客户端来源动态返回不同的代理地址
- **本机**访问 PAC → 自动降级为 `127.0.0.1:7890`（走环回，更快）
- **局域网设备**访问 PAC → 使用 `.env` 里配置的 `PROXY_TARGET`

**日志**：写入 `.cache/logs/mypac.log`，按天滚动（午夜切割），保留最近 7 天，过期自动清理。

改完 `.env` 后重启服务即可（`./run.sh`）。

> ⚠️ 注意：请确保代理软件（Clash/mihomo 等）已开启「允许局域网连接 / Allow LAN」，否则局域网设备无法连接 `PROXY_TARGET` 指定的代理地址。

## 🔄 自定义规则

编辑 `proxy.pac`，在 `FindProxyForURL` 中添加你的规则，保存即可。
**无需重启**——每次请求都会重新读取文件（默认 `Cache-Control: no-cache`）。

例如给某个域名强制直连：
```javascript
if (/(?:^|\.)(example\.com|foo\.cn)$/.test(host)) return 'DIRECT';
```

## ❓ FAQ：修改了 PAC 后客户端不生效？

**原因**：浏览器/操作系统会**缓存** PAC 脚本（通常 30 分钟以上）。即使服务端已更新，客户端仍可能使用旧的缓存规则。以下是各系统强制刷新 PAC 缓存的方法：

### Windows
1. 打开 **设置 → 网络和 Internet → 代理**
2. 找到「**自动检测代理配置**」（或「使用设置脚本」）
3. **关闭**开关 → 等待 2 秒 → **重新打开**
4. 重启浏览器

> ⚠️ `netsh winhttp reset proxy` 只重置 WinHTTP 层（系统服务用），**无法清除浏览器/系统代理的 PAC 缓存**，必须用上述开关方式刷新。

### macOS
1. **系统设置 → 网络 → Wi-Fi → 详细信息 → 代理**
2. 取消勾选「**自动代理配置**」→ 确定
3. 再次进入，重新勾选并填入 PAC URL → 确定
4. 重启浏览器

### Ubuntu / Linux (GNOME)
1. **设置 → 网络 → 网络代理**
2. 将模式从「**自动**」切换为「**无**」→ 应用
3. 再切回「**自动**」，重新填入 PAC URL → 应用
4. 重启浏览器

### 浏览器插件 (SwitchyOmega 等)
- 在插件设置中，切到「**直接连接**」→ 切回「**auto switch**」
- 或直接**禁用再启用**插件

> 💡 服务端已通过 `Cache-Control: no-cache, no-store, must-revalidate` 尽力阻止缓存，但部分系统/浏览器仍会固执缓存，此时需手动按上述方法刷新。

## 📁 文件结构

```
mypac/
├── proxy.pac             # PAC 规则模板（含 {{PROXY_TARGET}} 占位符，可热更新）
├── server.py             # HTTP 服务（零依赖，读取 .env 配置）
├── .env.example          # 配置模板（复制为 .env 使用）
├── .env                  # 你的本地配置（.gitignore 忽略，不入库）
├── .gitignore            # Git 忽略规则
├── .dockerignore         # Docker 构建忽略
├── Dockerfile            # Docker 镜像构建文件
├── docker-compose.yml    # Docker Compose 编排文件
├── README.md             # 本文档
├── run.sh                # 启动脚本（macOS/Linux，默认重启）
├── run.bat               # 启动脚本（Windows，默认重启）
└── .cache/logs/          # 运行时日志（按天滚动，保留 7 天，不入库）
```

## 🐳 Docker 部署

### 快速启动

```bash
# 1. 创建配置（修改 PROXY_TARGET 为你的代理地址）
cp .env.example .env

# 2. 构建并启动
docker compose up -d

# 3. 查看日志
docker compose logs -f

# 4. 停止
docker compose down
```

### 单条 docker 命令运行（不使用 Compose）

不想用 Compose，也可以直接用单条 `docker run` 启动：

```bash
# 1. 构建镜像（仅首次需要）
docker build -t mypac .

# 2. 单条命令运行
docker run -d \
  --name mypac \
  --restart unless-stopped \
  -p 10390:10390 \
  -e PROXY_TARGET=<宿主机局域网IP>:7890 \
  -e PAC_PORT=10390 \
  -e LOG_RETAIN_DAYS=7 \
  -e TZ=Asia/Shanghai \
  -v ./.cache/logs:/app/.cache/logs \
  mypac
```

常用操作：

```bash
docker logs -f mypac     # 查看日志
docker restart mypac     # 重启（改环境变量后需要）
docker rm -f mypac       # 停止并删除容器
```

> 💡 想让 PAC 规则热更新，可额外挂载：`-v ./proxy.pac:/app/proxy.pac:ro`
> 💡 若已通过 CI 推送到 DockerHub，可省略第 1 步构建，把镜像名换成 `docker.io/<你的用户名>/mypac:latest`。

### 说明

- **端口**：默认映射 `10390:10390`，在 `docker-compose.yml` 的 `ports` 中修改
- **配置**：通过 `.env` 文件挂载（只读），修改后需 `docker compose restart`
- **日志**：挂载到宿主机 `.cache/logs/`，按天滚动保留 7 天
- **PAC 规则**：挂载 `proxy.pac`（只读），修改后自动生效（无需重启容器）
- **健康检查**：容器内置 healthcheck，每 30 秒探测 PAC 服务是否响应
- **时区**：默认 `Asia/Shanghai`，让日志按本地午夜切割

### 自定义构建参数

编辑 `docker-compose.yml` 的 `environment` 段：
```yaml
environment:
  - PAC_PORT=10390                    # 容器内监听端口
  - PROXY_TARGET=127.0.0.1:7890  # 上游代理地址
  - LOG_RETAIN_DAYS=7                 # 日志保留天数
```

> ⚠️ Docker 模式下，`PROXY_TARGET` 应填**宿主机的局域网 IP**（不能用 127.0.0.1，否则容器会指向自身）。
