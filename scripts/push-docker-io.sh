#!/bin/bash
set -e

echo "🚀 Starting Docker Hub publication process..."
echo "============================================"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 默认配置
IMAGE_NAME="${IMAGE_NAME:-cloudflare-ddns}"
DOCKER_USERNAME="${DOCKER_USERNAME:-}"
VERSION="${VERSION:-latest}"

# 显示配置
echo -e "${BLUE}📋 Publication Configuration:${NC}"
echo "   Image Name: $IMAGE_NAME"
echo "   Version: $VERSION"
echo "   Platforms: $PLATFORMS"
echo "   Registry: Docker Hub"

echo "   DOCKER_USERNAME: $DOCKER_USERNAME"

# 检查必要的环境变量
if [ -z "$DOCKERHUB_TOKEN" ] && [ -z "$DOCKERHUB_PASSWORD" ]; then
    echo -e "${RED}❌ ERROR: DOCKERHUB_TOKEN or DOCKERHUB_PASSWORD environment variable is required${NC}"
    echo "   Get a token from: https://hub.docker.com/settings/security"
    exit 1
fi

if [ -z "$DOCKER_USERNAME" ]; then
    echo -e "${RED}❌ ERROR: DOCKER_USERNAME environment variable is required${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Docker Hub Username: $DOCKER_USERNAME${NC}"

# 完整的镜像地址
FULL_IMAGE_NAME="$DOCKER_USERNAME/$IMAGE_NAME:$VERSION"
echo -e "${BLUE}📦 Target Image: $FULL_IMAGE_NAME${NC}"

# 登录到 Docker Hub
echo -e "${YELLOW}🔐 Logging in to Docker Hub...${NC}"
if [ -n "$DOCKERHUB_TOKEN" ]; then
    echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKER_USERNAME" --password-stdin
else
    echo "$DOCKERHUB_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin
fi

docker publish "$FULL_IMAGE_NAME"