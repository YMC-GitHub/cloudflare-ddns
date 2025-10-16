#!/bin/bash

set -e

echo "=== 优化的多阶段构建 Windows GNU 版本 ==="

# 清理旧文件
rm -f cloudflare-ddns.exe

echo "🚀 开始优化的多阶段构建..."
docker build -f Dockerfile.window.gnu.alpine -t cf-ddns-windows-optimized .

echo "📦 提取优化的可执行文件..."
docker create --name extract-optimized cf-ddns-windows-optimized
docker cp extract-optimized:/output/cloudflare-ddns.exe ./
docker rm extract-optimized

# 清理
# rm -f Dockerfile.window.gnu.alpine

# 验证结果
if [ -f "cloudflare-ddns.exe" ]; then
    echo "✅ 优化的多阶段构建成功!"
    echo "📁 文件: cloudflare-ddns.exe"
    echo "💾 大小: $(ls -lh cloudflare-ddns.exe | awk '{print $5}')"
    echo "🔍 类型: $(file cloudflare-ddns.exe)"
    echo "🎯 构建阶段完成: base → deps → builder → output"
else
    echo "❌ 构建失败"
    exit 1
fi