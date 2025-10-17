# =============================================
# 多阶段构建：构建 + 发布到 GitHub Container Registry
# =============================================

# 基础构建参数
ARG USE_CHINA_MIRROR=false
ARG ALPINE_MIRROR=mirrors.aliyun.com
ARG RUST_MIRROR=tuna


# 阶段1: 构建阶段
FROM rust:1.90-alpine3.20 AS builder

# 继承构建参数
ARG USE_CHINA_MIRROR
ARG ALPINE_MIRROR
ARG RUST_MIRROR


# 条件性配置镜像源
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
        echo "🔧 Using China mirror: $ALPINE_MIRROR" && \
        sed -i "s|dl-cdn.alpinelinux.org|$ALPINE_MIRROR|g" /etc/apk/repositories; \
    else \
        echo "🌍 Using default Alpine sources"; \
    fi

# 安装构建依赖
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

# 先复制 Cargo 配置文件
# COPY .cargo/ .cargo/
# COPY Cargo.toml Cargo.lock ./

# 只复制必要的配置
COPY Cargo.toml ./

# 立即生成容器环境专用的 lockfile
# RUN cargo generate-lockfile

# 条件性配置 Cargo 国内源
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
        echo "🔧 Configuring Cargo China mirror: $RUST_MIRROR" && \
        mkdir -p /usr/local/cargo/ && \
        case "$RUST_MIRROR" in \
            "tuna") \
                cat > /usr/local/cargo/config << 'EOF' \
[source.crates-io]
replace-with = 'tuna'

[source.tuna]
registry = "https://mirrors.tuna.tsinghua.edu.cn/git/crates.io-index.git"

[net]
git-fetch-with-cli = true
EOF
                ;; \
            "ustc") \
                cat > /usr/local/cargo/config << 'EOF' \
[source.crates-io]
replace-with = 'ustc'

[source.ustc]
registry = "https://mirrors.ustc.edu.cn/crates.io-index/"

[net]
git-fetch-with-cli = true
EOF
                ;; \
        esac && \
        echo "✅ Cargo mirror configured: $RUST_MIRROR"; \
    else \
        echo "🌍 Using default Cargo sources"; \
        # 设置 git-fetch-with-cli 以提高稳定性 \
        mkdir -p /usr/local/cargo/ && \
        cat > /usr/local/cargo/config << 'EOF' \
[net]
git-fetch-with-cli = true
EOF
    fi


# 创建假的 src 目录来缓存依赖
RUN mkdir -p src && \
    echo "fn main() {}" > src/main.rs && \
    echo "// dummy lib" > src/lib.rs

# 构建依赖（缓存层）
RUN cargo fetch

RUN cargo build --release --target x86_64-unknown-linux-musl

# 现在复制真正的源代码
COPY src/ src/

# 真实构建
RUN rm -f target/x86_64-unknown-linux-musl/release/deps/cloudflare_ddns-* && \
    cargo build --release --target x86_64-unknown-linux-musl

# 优化二进制（移除调试符号并压缩）
RUN strip target/x86_64-unknown-linux-musl/release/cloudflare-ddns && \
    upx --best --lzma target/x86_64-unknown-linux-musl/release/cloudflare-ddns

# 验证构建结果
RUN echo "=== Build Verification ===" && \
    ls -lh target/x86_64-unknown-linux-musl/release/cloudflare-ddns && \
    file target/x86_64-unknown-linux-musl/release/cloudflare-ddns && \
    echo "=== Static Link Check ===" && \
    ldd target/x86_64-unknown-linux-musl/release/cloudflare-ddns 2>&1 | head -3

# 阶段2: 证书准备阶段
FROM alpine:3.20 AS certs

# 继承构建参数
ARG USE_CHINA_MIRROR
ARG ALPINE_MIRROR

# 条件性配置镜像源
RUN if [ "$USE_CHINA_MIRROR" = "true" ]; then \
        echo "🔧 Using China mirror in certs stage: $ALPINE_MIRROR" && \
        sed -i "s|dl-cdn.alpinelinux.org|$ALPINE_MIRROR|g" /etc/apk/repositories; \
    fi

# 安装证书和时区数据
RUN apk update && apk add --no-cache ca-certificates tzdata && \
    update-ca-certificates

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