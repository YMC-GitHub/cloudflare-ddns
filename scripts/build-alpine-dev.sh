#!/bin/bash
set -e

echo "=== 构建 Cloudflare DDNS ==="

# 构建 builder 镜像
docker build Dockerfile.alpine.dev -t cf-ddns-builder --target builder .

# 创建临时容器并提取二进制文件
container_id=$(docker create cf-ddns-builder)
docker cp $container_id:/app/target/x86_64-unknown-linux-musl/release/cloudflare-ddns ./cloudflare-ddns
docker rm $container_id

# 清理构建镜像
docker rmi cf-ddns-builder

echo "=== 构建完成 ==="
ls -lh cloudflare-ddns
echo "=== 文件信息 ==="
file cloudflare-ddns
echo "=== 依赖检查 ==="
ldd cloudflare-ddns 2>&1 || echo "静态链接，无外部依赖"