#!/bin/bash


echo "=== 构建优化镜像 ==="
# docker build -f Dockerfile.minimal -t cloudflare-ddns:optimized .
docker build --progress=plain -f Dockerfile.minimal -t cloudflare-ddns:optimized .
# docker build --no-cache -f Dockerfile.minimal -t cloudflare-ddns:optimized .



echo -e "\n=== 镜像大小 ==="
docker images cloudflare-ddns:optimized

echo -e "\n=== 层历史 ==="
docker history cloudflare-ddns:optimized

echo -e "\n=== 二进制文件信息 ==="
# docker run --rm cloudflare-ddns:optimized ls -lh /app/cloudflare-ddns
docker run --rm --entrypoint="" cloudflare-ddns:optimized /bin/sh -c "ls -lh /app/cloudflare-ddns"


echo -e "\n=== 实际磁盘使用 ==="
# docker run --rm cloudflare-ddns:optimized du -h /app/cloudflare-ddns
docker run --rm --entrypoint="" cloudflare-ddns:optimized /bin/sh -c "du -h /app/cloudflare-ddns"


# echo -e "\n=== 文件类型 ==="
# docker run --rm cloudflare-ddns:optimized file /app/cloudflare-ddns
# docker run --rm --entrypoint="" cloudflare-ddns:optimized /bin/sh -c "file /app/cloudflare-ddns"
# docker run --rm --user=root --entrypoint="" cloudflare-ddns:optimized /bin/sh -c "apk update ; apk add file ; file /app/cloudflare-ddns"

# docker run --rm --entrypoint="" cloudflare-ddns:optimized /bin/sh -c "ls -lh /app/cloudflare-ddns && echo '---' && head -c 4 /app/cloudflare-ddns | od -c"



# 检查是否静态链接
docker run --rm --entrypoint="" cloudflare-ddns:optimized /bin/sh -c "ldd /app/cloudflare-ddns 2>/dev/null || echo '可能是静态链接的二进制文件'"
# docker run --rm --entrypoint="" cloudflare-ddns:optimized sh -c "apk add file && file/app/cloudflare-ddns | grep -q 'statically linked' && echo '静态链接' || echo '动态链接'"

echo -e "\n=== 测试运行 ==="
docker run --rm cloudflare-ddns:optimized --help || echo "容器正常启动"

# 测试帮助信息
# docker run --rm cloudflare-ddns:optimized --help

# 测试版本信息  
docker run --rm cloudflare-ddns:optimized --version

# 测试平台信息
# docker run --rm cloudflare-ddns:optimized --show-platform

echo -e "\n=== 拷贝二进制文件到宿主机 ==="
rm ./cloudflare-ddns
CONTAINER_ID=$(docker create cloudflare-ddns:optimized)
docker cp $CONTAINER_ID:/app/cloudflare-ddns ./cloudflare-ddns
docker rm $CONTAINER_ID

echo -e "\n=== 变量挂载检查 ==="
docker run --rm -e CF_API_TOKEN="your_api_token" -e CF_ZONE_ID="your_zone_id" -e DNS_RECORD_NAME="example.com" --entrypoint="" cloudflare-ddns:optimized env
# docker run --rm -e CF_API_TOKEN="your_api_token" -e CF_ZONE_ID="your_zone_id" -e DNS_RECORD_NAME="example.com" cloudflare-ddns:optimized

# docker run --rm  --env-file .env --entrypoint="" cloudflare-ddns:optimized env