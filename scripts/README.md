
## 为 linux 平台构建

### 容器环境-musl版
```bash
./scripts/build-alpine-optimized.sh

# move to dist diretory and add musl suffix
# mv dist/cloudflare-ddns dist/cloudflare-ddns-musl

# move to dist diretory and add x86_64-unknown-linux-musl subdiretory
mkdir -p dist/x86_64-unknown-linux-musl
mv dist/cloudflare-ddns dist/x86_64-unknown-linux-musl/cloudflare-ddns

```

## 为 window 平台构建

### 真机环境-msvc版
```powershell
# cargo run -- --env-file .env

cargo build --release --target x86_64-pc-windows-msvc
# dir target\x86_64-pc-windows-msvc\release\cloudflare-ddns.exe
# target\x86_64-pc-windows-msvc\release\cloudflare-ddns.exe --version

# get file size
$fileSize = (Get-Item -Path "target\x86_64-pc-windows-msvc\release\cloudflare-ddns.exe").Length
$fileSizeInMB = [Math]::Round($fileSize / 1MB, 2)
Write-Output "File size: $fileSizeInMB MB"

# run this file

# copy this file to dist/cloudflare-ddns.exe
# make dist directory
New-Item -ItemType Directory -Force -Path "dist" | Out-Null
Copy-Item -Path "target\x86_64-pc-windows-msvc\release\cloudflare-ddns.exe" -Destination "dist\cloudflare-ddns.exe"

# move to dist diretory and add msvc suffix
# mv dist/cloudflare-ddns.exe dist/cloudflare-ddns-msvc.exe

# move to dist diretory and add x86_64-pc-windows-msvc subdiretory
New-Item -ItemType Directory -Force -Path "dist\x86_64-pc-windows-msvc" | Out-Null
Copy-Item -Path "target\x86_64-pc-windows-msvc\release\cloudflare-ddns.exe" -Destination "dist\x86_64-pc-windows-msvc\cloudflare-ddns.exe"  | Out-Null

```

### 容器环境-gnu版
- 使用轻量化镜像构建gnu版本
- 使用国内镜像为系统下载工具提速
- 使用国内镜像加速cargo下载依赖
- 使用多阶段构建
- 参考文件 dockerfilexxx
- 使用 rust:1.90-alpine3.20
- rust:1.90	 vs rust:slim vs rust:alpine vs rust:1.90-alpine3.20

```bash
./scripts/build-window-gnu-alpine.sh

# move to dist diretory and add gnu suffix
# mv dist/cloudflare-ddns.exe dist/cloudflare-ddns-gnu.exe

# move to dist diretory and add x86_64-pc-windows-gnu subdiretory
# mkdir -p dist/x86_64-pc-windows-gnu
# mv dist/cloudflare-ddns.exe dist/x86_64-pc-windows-gnu/cloudflare-ddns.exe

```

## 打包为镜像,并发布到docker hub
- docker.io
- ghcr.io
- mcr.microsoft.com
```bash
yours touch .github/workflows/push-docker-io.yml

# sh -c "rm -r /.github"

source .env
./scripts/push-docker-io.sh

docker publish cloudflare-ddns:latest
docker publish cloudflare-ddns:optimized
docker publish cloudflare-ddns:alpine
docker publish cloudflare-ddns:scratch

```