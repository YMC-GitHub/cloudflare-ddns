#!/bin/sh
set -e

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
    local flag_exit=$2

    if [ $status -eq 0 ]; then
        info_status "$msg_body" 0
    else
        info_status "$msg_body" 1
        [ $flag_exit -eq 0 ] && exit 1;
    fi
}

msg_padd(){
    local msg=$1
    local msg_max_len=$2
    local msg_len=${#msg}
    local msg_fill_length=$((($msg_max_len-$msg_len+2)/2))
    local msg_padding=$(printf "%-${msg_fill_length}s" | tr ' ' '-')
    echo "$msg_padding-$msg-$msg_padding" | cut -c 1-$msg_max_len
}

info_step(){
    local msg=$1
    msg_padd "$msg" 60
}

load_env_from_file(){
    local step_name="load environment variables from .env file"
    if [ -f.env ]; then
        info_step "$step_name"
        info_status "NETWORK:$NETWORK" $?
        export $(grep -v '^#' .env | xargs)
        info_status "$step_name" $?
        info_status "NETWORK:$NETWORK" $?
    fi
}

load_env_from_default() {
    local step_name="Load default values for variables"
    info_step "$step_name"
    info_status "NETWORK:$NETWORK" $?
    # Set default values for variables
    NETWORK=${NETWORK:-"cn"}
    APT_REPO_CN=${APT_REPO_CN:-"mirrors.aliyun.com"}
    APT_REPO_GLOBAL=${APT_REPO_GLOBAL:-"deb.debian.org"}
    APT_REPO_FILE=${APT_REPO_FILE:-"/etc/apt/sources.list.d/debian.sources"}
    PIP_REPO_CN=${PIP_REPO_CN:-"https://pypi.tuna.tsinghua.edu.cn/simple"}
    PIP_TRUSTED_HOST=${PIP_TRUSTED_HOST:-"pypi.tuna.tsinghua.edu.cn"}
    PIP_REPO_GLOBAL=${PIP_REPO_GLOBAL:-"https://pypi.org/simple"}
    POETRY_REPO_CN=${POETRY_REPO_CN:-"https://pypi.tuna.tsinghua.edu.cn/simple"}
    POETRY_REPO_GLOBAL=${POETRY_REPO_GLOBAL:-"https://pypi.org/simple"}
    info_status "$step_name" $?
    info_status "NETWORK:$NETWORK" $?
}


set_apk_repo(){
    local step_name="set apk repo"
    info_step "$step_name"
    if [ "$NETWORK" = "cn" ]; then
        sed -i "s|dl-cdn.alpinelinux.org|${APK_REPO_CN}|g" /etc/apk/repositories
        check_result "$step_name (cn)" $? 1
    else
        sed -i "s|dl-cdn.alpinelinux.org|${APK_REPO_GLOBAL}|g" /etc/apk/repositories
        check_result "$step_name (global)" $? 1
    fi
    check_result "$step_name" $? 1
}

set_pip_repo(){
    local step_name="set pip repo"
    info_step "$step_name"
    if [ "$NETWORK" = "cn" ]; then
        domain=$(echo $PIP_REPO_CN | awk -F/ '{print $3}')
        mkdir -p /etc/pip
        cat > /etc/pip.conf <<EOF
[global]
index-url = $PIP_REPO_CN
trusted-host = $domain
EOF
        check_result "$step_name (cn)" $? 1
    fi
    check_result "$step_name" $? 1
}

set_poetry_repo(){
    local step_name="set poetry repo"
    info_step "$step_name"
    if [ "$NETWORK" = "cn" ]; then
        info_status "$step_name (cn)" 2
        poetry config repositories.pypi ${POETRY_REPO_CN};
    else
        info_status "$step_name (global)" 2
        poetry config repositories.pypi ${POETRY_REPO_GLOBAL};
    fi
    check_result "$step_name" $? 1
}

setup_poetry(){
    local step_name="setup poetry"
    info_step "$step_name"

    pip install --root-user-action ignore --no-cache-dir --upgrade pip > /dev/null 2>&1;
    info_status "update pip" $?

    pip install --root-user-action ignore --no-cache-dir  poetry  > /dev/null 2>&1;
    info_status "install poetry" $?

    if [ "$NETWORK" = "cn" ]; then
        poetry config repositories.pypi ${POETRY_REPO_CN};
        info_status "config repositories.pypi (cn)" $?
    else
        poetry config repositories.pypi ${POETRY_REPO_GLOBAL};
        info_status "config repositories.pypi (global)" $?
    fi
    poetry config virtualenvs.in-project true
    info_status "config virtualenvs.in-project (true)" $?

    if [ ! -f pyproject.toml ]; then
        info_status "poetry install main package (skip)" 0
        return
    fi
    poetry install --no-interaction --no-ansi --only main
    check_result "$step_name" $? 1
}

dup_env_path(){
    local step_name="dup env path"
    info_step "$step_name"
    PATH=$(echo "$PATH" | tr ':' '\n' | sort -u | tr '\n' ':' | sed 's/:$//')
    echo "$PATH"

    export PATH=$PATH
    echo "export PATH=\$(echo \"\$PATH\" | tr ':' '\n' | sort -u | tr '\n' ':' | sed 's/:$//')" >> /etc/profile
    echo "echo \$PATH"
    info_status "$step_name" 0
}

default_api() {
    local api="$1"
    api=$(echo "$api" | tr '[:upper:]' '[:lower:]')
    case "$api" in
        set_apk_repo) set_apk_repo;;
        set_pip_repo) set_pip_repo;;
        dup_env_path) dup_env_path;;
        set_poetry_repo) set_poetry_repo;;
        setup_poetry) setup_poetry;;
        all) set_apk_repo;set_pip_repo;dup_env_path;;
        *) echo "usage: $0 [set_apk_repo|set_pip_repo|dup_env_path|set_poetry_repo|setup_poetry|all]";;
    esac
}

load_env_from_file
load_env_from_default
default_api "$@"