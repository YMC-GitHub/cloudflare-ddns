多阶段构建：构建 + 发布到 Docker Hub
# =============================================

# 阶段1: 构建阶段
FROM rust:1.90-alpine3.20 AS builder

# 镜像源替换（可选，用于加速）
RUN sed -i 's|dl-cdn.alpinelinux.org|mirrors.ustc.edu.cn|g' /etc/apk/repositories

RUN apk update && apk add --no-cache \
    git \
    gcc \
    musl-dev \
    openssl-dev \
    build-base \
    pkgconfig \
    openssl-libs-static \
    upx \
    file

WORKDIR /app

# 先复制 Cargo 配置文件（利用Docker缓存）
COPY .cargo/ .cargo/
COPY Cargo.toml Cargo.lock ./

# 创建假的 src 目录来缓存依赖
RUN mkdir -p src && \
    echo "fn main() {}" > src/main.rs && \
    echo "// dummy lib" > src/lib.rs

# 构建依赖（缓存层）
RUN cargo build --release --target x86_64-unknown-linux-musl

# 现在复制真正的源代码
COPY src/ src/

# 清理假的 main.rs 并重新构建
RUN rm -f target/x86_64-unknown-linux-musl/release/deps/cloudflare_ddns-* && \
    cargo build --release --target x86_64-unknown-linux-musl

# 移除调试符号并压缩
RUN strip /app/target/x86_64-unknown-linux-musl/release/cloudflare-ddns
RUN upx --best --lzma /app/target/x86_64-unknown-linux-musl/release/cloudflare-ddns

# 阶段2: 证书准备阶段
FROM alpine:3.20 AS certs
RUN sed -i 's|dl-cdn.alpinelinux.org|mirrors.aliyun.com|g' /etc/apk/repositories
RUN apk update && apk add --no-cache ca-certificates tzdata
RUN update-ca-certificates

# 阶段3: 最终运行镜像（scratch）
FROM scratch AS runtime

# 复制 SSL 证书（必须，因为你的应用需要 HTTPS）
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# 时区信息
COPY --from=certs /usr/share/zoneinfo /usr/share/zoneinfo
ENV TZ=Asia/Shanghai

# 复制二进制文件
COPY --from=builder /app/target/x86_64-unknown-linux-musl/release/cloudflare-ddns /app/cloudflare-ddns

# 设置入口点
ENTRYPOINT ["/app/cloudflare-ddns"]