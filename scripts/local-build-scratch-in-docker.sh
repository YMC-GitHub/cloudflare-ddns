#!/bin/bash
set -e

# 配置信息
IMAGE_NAME="cloudflare-ddns"
TAG="scratch"
USE_CHINA_MIRROR=${USE_CHINA_MIRROR:-false}
ALPINE_MIRROR=${ALPINE_MIRROR:-mirrors.aliyun.com}
RUST_MIRROR=${RUST_MIRROR:-tuna}
TARGET=${TARGET:-runtime}

# 输出样式函数
info_status(){
    local msg_body=$1
    local status=$2
    local msg_success="✅"
    local msg_failed="❌"
    local msg_warn="ℹ️"

    if [ $status -eq 0 ]; then
        echo "$msg_success $msg_body"
    elif [ $status -eq 1 ]; then
        echo "$msg_failed $msg_body"
    else
        echo "$msg_warn $msg_body"
    fi
}

check_result(){
    local status=$?
    local msg_body=$1
    local flag_exit=${2:-1}

    if [ $status -eq 0 ]; then
        info_status "$msg_body" 0
    else
        info_status "$msg_body" 1
        [ $flag_exit -eq 1 ] && exit 1
    fi
}

msg_padd(){
    local msg=$1
    local msg_max_len=${2:-60}
    local msg_len=${#msg}
    local msg_fill_length=$((($msg_max_len-$msg_len+2)/2))
    local msg_padding=$(printf "%-${msg_fill_length}s" | tr ' ' '-')
    echo "$msg_padding-$msg-$msg_padding" | cut -c 1-$msg_max_len
}

info_step(){
    local msg=$1
    msg_padd "$msg" 60
}

# API函数：参数解析
parse_arguments() {
    local step_name="解析构建参数"
    info_step "$step_name"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --china-mirror)
                USE_CHINA_MIRROR=true
                shift
                ;;
            --alpine-mirror)
                ALPINE_MIRROR="$2"
                shift 2
                ;;
            --rust-mirror)
                RUST_MIRROR="$2"
                shift 2
                ;;
            --tag)
                TAG="$2"
                shift 2
                ;;
            --target)
                TARGET="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                info_status "未知参数: $1" 1
                show_help
                exit 1
                ;;
        esac
    done
    
    info_status "镜像名称: $IMAGE_NAME:$TAG" 2
    info_status "使用国内镜像: $USE_CHINA_MIRROR" 2
    info_status "Alpine镜像源: $ALPINE_MIRROR" 2
    info_status "Rust镜像源: $RUST_MIRROR" 2
    info_status "构建目标: $TARGET" 2
    info_status "$step_name" 0
}

# API函数：显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --china-mirror         使用国内镜像源"
    echo "  --alpine-mirror URL    设置Alpine镜像源 (默认: mirrors.aliyun.com)"
    echo "  --rust-mirror SOURCE   设置Rust镜像源 (默认: tuna)"
    echo "  --tag TAG              设置镜像标签 (默认: scratch)"
    echo "  --target TARGET        设置构建目标 (默认: runtime)"
    echo "  --help, -h             显示此帮助信息"
    echo ""
    echo "环境变量:"
    echo "  USE_CHINA_MIRROR       使用国内镜像源 (true/false)"
    echo "  ALPINE_MIRROR          Alpine镜像源地址"
    echo "  RUST_MIRROR           Rust镜像源"
    echo "  TARGET                构建目标"
}

# API函数：验证配置
validate_config() {
    local step_name="验证构建配置"
    info_step "$step_name"
    
    # 验证镜像名称
    if [[ -z "$IMAGE_NAME" ]]; then
        info_status "镜像名称不能为空" 1
        exit 1
    fi
    
    # 验证标签
    if [[ -z "$TAG" ]]; then
        info_status "镜像标签不能为空" 1
        exit 1
    fi
    
    # 验证目标
    if [[ -z "$TARGET" ]]; then
        info_status "构建目标不能为空" 1
        exit 1
    fi
    
    info_status "$step_name" 0
}

# API函数：环境检查
check_environment() {
    local step_name="检查构建环境"
    info_step "$step_name"
    
    # 检查Docker是否可用
    if ! command -v docker &> /dev/null; then
        info_status "Docker未安装或未在PATH中" 1
        exit 1
    fi
    
    # 检查Docker守护进程是否运行
    if ! docker info &> /dev/null; then
        info_status "Docker守护进程未运行" 1
        exit 1
    fi
    
    info_status "Docker版本: $(docker --version | cut -d' ' -f3 | tr -d ',')" 2
    info_status "$step_name" 0
}

# API函数：构建Docker镜像
build_image() {
    local step_name="构建Docker镜像"
    info_step "$step_name"
    
    local build_args=(
        "--build-arg USE_CHINA_MIRROR=$USE_CHINA_MIRROR"
        "--build-arg ALPINE_MIRROR=$ALPINE_MIRROR"
        "--build-arg RUST_MIRROR=$RUST_MIRROR"
        "--target $TARGET"
        "-t $IMAGE_NAME:$TAG"
        "."
    )
    
    info_status "执行命令: docker build ${build_args[*]}" 2
    docker build "${build_args[@]}"
    
    check_result "$step_name" 1
}

# API函数：镜像大小分析
analyze_image_size() {
    local step_name="镜像大小分析"
    local imagename=$IMAGE_NAME:$TAG
    
    info_step "$step_name"
    docker images $imagename
    check_result "$step_name" 0
}

# API函数：镜像层分析
analyze_image_layers() {
    local step_name="镜像层分析"
    local imagename=$IMAGE_NAME:$TAG
    
    info_step "$step_name"
    docker history $imagename
    check_result "$step_name" 0
}

# API函数：二进制文件分析
analyze_binary() {
    local step_name="二进制文件分析"
    local imagename=$IMAGE_NAME:$TAG
    
    info_step "$step_name"
    
    # 文件详细信息
    info_step "文件详细信息"
    docker run --rm --entrypoint="" $imagename /bin/sh -c "ls -lh /app/cloudflare-ddns"
    check_result "文件详细信息" 0
    
    # 磁盘使用情况
    info_step "磁盘使用情况"
    docker run --rm --entrypoint="" $imagename /bin/sh -c "du -h /app/cloudflare-ddns"
    check_result "磁盘使用情况" 0
    
    info_status "$step_name" 0
}

# API函数：功能测试
test_functionality() {
    local step_name="功能测试"
    local imagename=$IMAGE_NAME:$TAG
    
    info_step "$step_name"
    
    # 测试版本信息
    info_step "测试版本信息"
    docker run --rm $imagename --version
    check_result "版本信息测试" 0
    
    # 测试配置显示
    info_step "测试配置显示"
    if [ -f .env.example ]; then
        docker run --rm --env-file .env.example $imagename --show-config
        check_result "配置显示测试" 0
    else
        info_status "缺少.env.example文件，跳过配置测试" 2
    fi
    
    info_status "$step_name" 0
}

# API函数：提取二进制文件
extract_binary() {
    local step_name="提取二进制文件"
    info_step "$step_name"
    
    local binary_name="./cloudflare-ddns"
    
    # 清理旧文件
    rm -f $binary_name
    
    # 创建容器并提取文件
    local container_id=$(docker create $IMAGE_NAME:$TAG)
    docker cp $container_id:/app/cloudflare-ddns $binary_name
    docker rm $container_id > /dev/null 2>&1
    
    if [ -f "$binary_name" ]; then
        info_status "二进制文件提取成功" 0
        info_step "提取的文件信息"
        ls -lh $binary_name
        file $binary_name 2>/dev/null || info_status "无法获取文件类型信息" 2
    else
        info_status "二进制文件提取失败" 1
    fi
    
    info_status "$step_name" 0
}

# API函数：清理资源
cleanup() {
    local step_name="清理资源"
    local imagename=$IMAGE_NAME:$TAG
    
    info_step "$step_name"
    
    # 询问是否清理镜像
    read -p "是否删除构建的镜像 $imagename? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker rmi $imagename
        info_status "已删除镜像: $imagename" 0
    else
        info_status "保留镜像: $imagename" 2
    fi
    
    info_status "$step_name" 0
}

# API函数：完整构建流程
build_full() {
    local step_name="完整构建流程"
    info_step "$step_name"
    
    check_environment
    validate_config
    build_image
    analyze_image_size
    analyze_image_layers
    analyze_binary
    test_functionality
    extract_binary
    
    info_status "$step_name" 0
}

# API函数：快速构建
build_quick() {
    local step_name="快速构建"
    info_step "$step_name"
    
    check_environment
    validate_config
    build_image
    analyze_image_size
    test_functionality
    
    info_status "$step_name" 0
}

# API函数：仅构建
build_only() {
    local step_name="仅构建镜像"
    info_step "$step_name"
    
    check_environment
    validate_config
    build_image
    analyze_image_size
    
    info_status "$step_name" 0
}

# 主执行流程
main() {
    local command=${1:-"build_full"}
    
    case "$command" in
        "build_full")
            build_full
            ;;
        "build_quick")
            build_quick
            ;;
        "build_only")
            build_only
            ;;
        "analyze")
            analyze_image_size
            analyze_image_layers
            # analyze_binary
            ;;
        "test")
            test_functionality
            ;;
        "extract")
            extract_binary
            ;;
        "cleanup")
            cleanup
            ;;
        "help")
            show_help
            ;;
        *)
            parse_arguments "$@"
            build_full
            ;;
    esac
}

# 显示欢迎信息
echo "$(msg_padd "Cloudflare DDNS 构建工具" 60)"
echo "版本: 1.0.0"
echo "镜像: $IMAGE_NAME"
echo ""

# 执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi