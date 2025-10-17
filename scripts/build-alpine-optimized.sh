#!/bin/bash


# imagename=cloudflare-ddns:scratch
imagename=cloudflare-ddns:optimized

# docker history $imagename

# echo "=== 构建优化镜像 ==="
docker rmi $imagename -f || echo "旧镜像不存在"
# docker build -f Dockerfile.minimal -t $imagename .
# docker build --progress=plain -f Dockerfile.minimal -t $imagename .
docker build --no-cache -f Dockerfile.minimal -t $imagename .



echo -e "\n=== 镜像大小 ==="
docker images $imagename

echo -e "\n=== 层历史 ==="
docker history $imagename

echo -e "\n=== 二进制文件信息 ==="
# docker run --rm $imagename ls -lh /app/cloudflare-ddns
docker run --rm --entrypoint="" $imagename /bin/sh -c "ls -lh /app/cloudflare-ddns"


echo -e "\n=== 实际磁盘使用 ==="
# docker run --rm $imagename du -h /app/cloudflare-ddns
docker run --rm --entrypoint="" $imagename /bin/sh -c "du -h /app/cloudflare-ddns"


# echo -e "\n=== 文件类型 ==="
# docker run --rm $imagename file /app/cloudflare-ddns
# docker run --rm --entrypoint="" $imagename /bin/sh -c "file /app/cloudflare-ddns"
# docker run --rm --user=root --entrypoint="" $imagename /bin/sh -c "apk update ; apk add file ; file /app/cloudflare-ddns"

# docker run --rm --entrypoint="" $imagename /bin/sh -c "ls -lh /app/cloudflare-ddns && echo '---' && head -c 4 /app/cloudflare-ddns | od -c"



# 检查是否静态链接
docker run --rm --entrypoint="" $imagename /bin/sh -c "ldd /app/cloudflare-ddns 2>/dev/null || echo '可能是静态链接的二进制文件'"
# docker run --rm --entrypoint="" $imagename sh -c "apk add file && file/app/cloudflare-ddns | grep -q 'statically linked' && echo '静态链接' || echo '动态链接'"

echo -e "\n=== 测试运行 ==="
docker run --rm $imagename --help || echo "容器正常启动"

# 测试帮助信息
# docker run --rm $imagename --help

# 测试版本信息  
docker run --rm $imagename --version

# 测试平台信息
# docker run --rm $imagename --show-platform

echo -e "\n=== 拷贝二进制文件到宿主机 ==="
rm ./cloudflare-ddns
CONTAINER_ID=$(docker create $imagename)
docker cp $CONTAINER_ID:/app/cloudflare-ddns ./cloudflare-ddns
docker rm $CONTAINER_ID

echo -e "\n=== 变量挂载检查 ==="
# docker run --rm -e CF_API_TOKEN="your_api_token" -e CF_ZONE_ID="your_zone_id" -e DNS_RECORD_NAME="example.com" --entrypoint="" $imagename env
# docker run --rm -e CF_API_TOKEN="your_api_token" -e CF_ZONE_ID="your_zone_id" -e DNS_RECORD_NAME="example.com" $imagename
docker run --rm  --env-file .env --entrypoint="" $imagename env