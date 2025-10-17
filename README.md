
# Cloudflare DDNS Docker Image User Manual

## Image Introduction

A lightweight Docker image application that dynamically binds local public IP to custom domains. Automatically detects public IP changes and creates/updates records using Cloudflare DDNS API. Implemented in Rust.

### Available Tags
- `scratch` (3.49MB) - Built on `alpine` and deployed on `scratch` as runtime image
- ~~`alpine` (16.5MB) - Built on `alpine` and deployed on `alpine` as runtime image~~
- `latest` (3.49.5MB) - Uses `scratch` version as latest image

## Quick Start

### 1. Pull Image
```bash
# from docker.io
docker pull yemiancheng/cloudflare-ddns:latest

# from ghcr.io
docker pull ghcr.io/ymc-github/cloudflare-ddns:latest
```

### 2. Prepare Configuration File
Create `.env` configuration file:
```bash
cat > .env << 'EOF'
# Cloudflare API Configuration
CF_API_TOKEN=your_api_token_here
CF_ZONE_ID=your_zone_id_here

# DNS Record Configuration
DNS_RECORD_NAME=example.com,sub.example.com
DNS_RECORD_TYPE=A
PROXY=false
TTL=120

# Application Configuration
UPDATE_INTERVAL=300
RUN_ON_START=true
EOF
```

### 3. Run Container
```bash
# docker run --rm yemiancheng/cloudflare-ddns:latest --help
# docker run --rm yemiancheng/cloudflare-ddns:latest --version
# docker run --rm yemiancheng/cloudflare-ddns:latest --show-platform

docker run -d \
  --name cloudflare-ddns \
  --restart unless-stopped \
  --env-file .env \
  yemiancheng/cloudflare-ddns:latest
```

#### Runtime Log Example
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

## Configuration Guide

### Required Environment Variables
| Environment Variable | Description | Example |
|---------------------|-------------|---------|
| `CF_API_TOKEN` | Cloudflare API Token | `yourtoken123` |
| `CF_ZONE_ID` | Cloudflare Zone ID | `yourzoneid456` |
| `DNS_RECORD_NAME` | Domain names to update (multiple separated by commas) | `example.com,sub.example.com` |

### Optional Environment Variables
| Environment Variable | Default Value | Description |
|---------------------|---------------|-------------|
| `DNS_RECORD_TYPE` | A | DNS record type (A/AAAA) |
| `PROXY` | false | Enable Cloudflare proxy |
| `TTL` | 120 | DNS record TTL (seconds) |
| `UPDATE_INTERVAL` | 300 | IP check interval (seconds) |
| `RUN_ON_START` | true | Execute update immediately on container start |

## Container Management Commands

### Check Running Status
```bash
docker ps -f name=cloudflare-ddns
```

### View Real-time Logs
```bash
docker logs -f cloudflare-ddns
```

### Enter Container
```bash
docker exec -it cloudflare-ddns sh
```

### Stop and Remove Container
```bash
docker stop cloudflare-ddns && docker rm cloudflare-ddns
```

### Restart Service
```bash
docker restart cloudflare-ddns
```

## Using Docker Compose

### Create docker-compose.yml
```yaml
version: '3.8'
services:
  cloudflare-ddns:
    image: yemiancheng/cloudflare-ddns:latest
    container_name: cloudflare-ddns
    restart: unless-stopped
    env_file: .env
```

### Start Service
```bash
docker-compose up -d
```

### Check Service Status
```bash
docker-compose ps
```

### Stop Service
```bash
docker-compose down
```

## Configuration Guide

### Obtaining Cloudflare API Token
1. Log in to Cloudflare dashboard
2. Go to 「My Profile」→「API Tokens」
3. Click 「Create Token」
4. Select 「Edit zone DNS」template
5. Choose the domain zone to authorize
6. Copy the generated Token

### Obtaining Zone ID
1. In Cloudflare domain control panel
2. Find the 「API」section at bottom right of the page
3. Copy the 「Zone ID」

### Multiple Domain Configuration
Supports updating multiple domain records simultaneously:
```ini
DNS_RECORD_NAME=example.com,www.example.com,subdomain.example.com
```

### IPv6 Support
To update AAAA records (IPv6): (Untested)
```ini
DNS_RECORD_TYPE=AAAA
```

## Troubleshooting

### View Detailed Logs
```bash
docker logs cloudflare-ddns
```

### Test Configuration
```bash
docker run -it --rm --env-file .env yemiancheng/cloudflare-ddns:latest
```

### Common Errors
1. **Authentication Failed**: Check if API Token is correct
2. **Zone ID Error**: Confirm Zone ID matches the domain
3. **Insufficient Permissions**: Ensure API Token has DNS edit permissions

## Version Update
```bash
docker pull yemiancheng/cloudflare-ddns:latest
docker-compose down
docker-compose up -d
```

## Technical Support
If you encounter issues, please submit an Issue to the project repository:
[https://github.com/ymc-github/cloudflare-ddns](https://github.com/ymc-github/cloudflare-ddns)

## License
MIT License
