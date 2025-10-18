# Cloudflare DDNS Docker 镜像使用手册

## 镜像简介

一个轻量级的动态绑定本地公网IP到自定义域名的 Docker 镜像应用。能够自动检测公网 IP 变化并以 Cloudflare DDNS API 创建/更新记录。基于rust实现。

### 可用标签
- `scratch` (3.49MB) - 基于 `alpine`构建 并部署于 `scratch` 作为运行时镜像
- ~~`alpine` (16.5MB) - 基于 `alpine`构建 并部署于 `alpine` 作为运行时镜像~~
- `latest` (3.49.5MB) - 使用 `scratch` 版作为 latest 镜像


## 快速开始

### 1. 拉取镜像
```bash
# from docker.io
docker pull yemiancheng/cloudflare-ddns:latest

# from ghcr.io
docker pull ghcr.io/ymc-github/cloudflare-ddns:latest
```

### 2. 准备配置文件
创建 `.env` 配置文件：
```bash
cat > .env << 'EOF'
# Cloudflare API 配置
CF_API_TOKEN=your_api_token_here
CF_ZONE_ID=your_zone_id_here

# DNS记录配置
DNS_RECORD_NAME=example.com,sub.example.com
DNS_RECORD_TYPE=A
PROXY=false
TTL=120

# 应用配置
UPDATE_INTERVAL=300
RUN_ON_START=true
EOF
```

### 3. 运行容器
```bash
# docker run --rm yemiancheng/cloudflare-ddns:latest --help
# docker run --rm yemiancheng/cloudflare-ddns:latest --version
# docker run --rm yemiancheng/cloudflare-ddns:latest --show-platform
# docker run --rm -env-file .env yemiancheng/cloudflare-ddns:latest --show-config
docker run -d --name cloudflare-ddns --restart unless-stopped --env-file .env yemiancheng/cloudflare-ddns:latest

```

#### 运行日志示例
```
[2025-10-17T13:22:19Z INFO  cloudflare_ddns] 🚀 Starting Cloudflare DDNS Client on linux-x86_64
=======================Configuration=======================
✅ Platform: linux-x86_64
✅ Zone ID: XX
✅ Record type: A
✅ Proxy enabled: false
✅ TTL: 120 seconds
✅ Host identifier: abc61d2207bf
✅ Network: cn
✅ Monitoring 3 domain(s): ["me.xx.top", "hn.xx.top", "ai.xx.top"]
====================Initial DDNS Update====================
-----------------------get public IP-----------------------
[2025-10-17T13:22:19Z DEBUG reqwest::connect] starting new connection: https://api.ipify.org/
[2025-10-17T13:22:24Z DEBUG reqwest::connect] starting new connection: https://ident.me/
✅ 2025-10-17 13:22:28 - Public IP address XX.XX.XXX.XA
-------------get DNS record for me.xx.top-------------
[2025-10-17T13:22:28Z DEBUG reqwest::connect] starting new connection: https://api.cloudflare.com/
✅ 2025-10-17 13:22:30 - DNS record me.xx.top found
✅ 2025-10-17 13:22:30 - IP change detected: Record IP XX.XX.XXX.XB, Current IP XX.XX.XXX.XA for me.xx.top
------------update DNS record for me.xx.top------------
[2025-10-17T13:22:31Z INFO  cloudflare_ddns] ✅ Successfully updated DNS record: me.xx.top -> XX.XX.XXX.XA
✅ 2025-10-17 13:22:31 - DNS record me.xx.top updated to XX.XX.XXX.XA
-------------get DNS record for hn.xx.top-------------
✅ 2025-10-17 13:22:31 - DNS record hn.xx.top found
✅ 2025-10-17 13:22:31 - IP change detected: Record IP XX.XX.XXX.XB, Current IP XX.XX.XXX.XA for hn.xx.top
------------update DNS record for hn.xx.top------------
[2025-10-17T13:22:31Z INFO  cloudflare_ddns] ✅ Successfully updated DNS record: hn.xx.top -> XX.XX.XXX.XA
✅ 2025-10-17 13:22:31 - DNS record hn.xx.top updated to XX.XX.XXX.XA
-------------get DNS record for ai.xx.top-------------
✅ 2025-10-17 13:22:32 - DNS record ai.xx.top found
✅ 2025-10-17 13:22:32 - IP change detected: Record IP XX.XX.XXX.XB, Current IP XX.XX.XXX.XA for ai.xx.top
------------update DNS record for ai.xx.top------------
[2025-10-17T13:22:32Z INFO  cloudflare_ddns] ✅ Successfully updated DNS record: ai.xx.top -> XX.XX.XXX.XA
✅ 2025-10-17 13:22:32 - DNS record ai.xx.top updated to XX.XX.XXX.XA
============Starting update loop (300s interval)============
```


## 配置说明

### 必需环境变量
| 环境变量 | 说明 | 示例 |
|---------|------|------|
| `CF_API_TOKEN` | Cloudflare API Token | `yourtoken123` |
| `CF_ZONE_ID` | Cloudflare Zone ID | `yourzoneid456` |
| `DNS_RECORD_NAME` | 要更新的域名（多个用逗号分隔） | `example.com,sub.example.com` |

### 可选环境变量
| 环境变量 | 默认值 | 说明 |
|---------|--------|------|
| `DNS_RECORD_TYPE` | A | DNS记录类型（A/AAAA） |
| `PROXY` | false | 是否启用Cloudflare代理 |
| `TTL` | 120 | DNS记录TTL（秒） |
| `UPDATE_INTERVAL` | 300 | IP检查间隔（秒） |
| `RUN_ON_START` | true | 容器启动时立即执行更新 |

## 容器管理命令

### 查看运行状态
```bash
docker ps -f name=cloudflare-ddns
```

### 查看实时日志
```bash
docker logs -f cloudflare-ddns
```

### 进入容器
```bash
docker exec -it cloudflare-ddns sh
```

### 停止并删除容器
```bash
docker stop cloudflare-ddns && docker rm cloudflare-ddns
```

### 重启服务
```bash
docker restart cloudflare-ddns
```

## 使用 Docker Compose

### 创建 docker-compose.yml
```yaml
version: '3.8'
services:
  cloudflare-ddns:
    image: yemiancheng/cloudflare-ddns:latest
    container_name: cloudflare-ddns
    restart: unless-stopped
    env_file: .env
```

### 启动服务
```bash
docker-compose up -d
```

### 查看服务状态
```bash
docker-compose ps
```

### 停止服务
```bash
docker-compose down
```

## 配置指南

### 获取 Cloudflare API Token
1. 登录 Cloudflare 控制台
2. 进入「My Profile」→「API Tokens」
3. 点击「Create Token」
4. 选择「Edit zone DNS」模板
5. 选择需要授权的域名区域
6. 复制生成的 Token

### 获取 Zone ID
1. 在 Cloudflare 域名控制面板
2. 在页面右下角找到「API」区域
3. 复制「Zone ID」

### 多域名配置
支持同时更新多个域名记录：
```ini
DNS_RECORD_NAME=example.com,www.example.com,subdomain.example.com
```

### IPv6 支持
如需更新 AAAA 记录（IPv6）：(未测试)
```ini
DNS_RECORD_TYPE=AAAA
```

## 故障排除

### 查看详细日志
```bash
docker logs cloudflare-ddns
```

### 测试配置
```bash
docker run -it --rm --env-file .env yemiancheng/cloudflare-ddns:latest
```

### 常见错误
1. **认证失败**：检查 API Token 是否正确
2. **Zone ID 错误**：确认 Zone ID 与域名匹配
3. **权限不足**：确保 API Token 具有 DNS 编辑权限

## 版本更新
```bash
docker pull yemiancheng/cloudflare-ddns:latest
docker-compose down
docker-compose up -d
```

## 技术支持
如遇问题，请提交 Issue 至项目仓库：
[https://github.com/ymc-github/cloudflare-ddns](https://github.com/ymc-github/cloudflare-ddns)

## 许可证
MIT OR Apache-2.0
