#!/bin/bash
# 通用重试函数库（增强调用：UA/Referer/压缩/跟随跳转）
# 用法：source lib-retry.sh; retry_http command max_retries timeout

DEFAULT_MAX_RETRIES=3
DEFAULT_RETRY_INTERVAL=2
DEFAULT_TIMEOUT=30

HTTP_UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0 Safari/537.36"
HTTP_REF="https://quote.eastmoney.com/"

retry_http() {
    local cmd="$1"
    local max_retries=${2:-$DEFAULT_MAX_RETRIES}
    local timeout=${3:-$DEFAULT_TIMEOUT}
    local retry_interval=$DEFAULT_RETRY_INTERVAL
    local result
    for ((i=1; i<=max_retries; i++)); do
        echo "第 $i 次尝试..." >&2
        result=$(eval "$cmd" 2>/dev/null)
        if [ -n "$result" ] && [ ${#result} -gt 50 ]; then
            echo "$result"; return 0
        fi
        if [ $i -lt $max_retries ]; then
            echo "第 $i 次失败，${retry_interval}秒后重试..." >&2
            sleep $retry_interval
        fi
    done
    echo "❌ 经过 $max_retries 次尝试后仍无法获取数据" >&2
    return 1
}

curl_retry() {
    local url="$1"
    local max_retries=${2:-$DEFAULT_MAX_RETRIES}
    local timeout=${3:-$DEFAULT_TIMEOUT}
    local retry_interval=$DEFAULT_RETRY_INTERVAL
    local data=""
    for ((i=1; i<=max_retries; i++)); do
        echo "[重试 $i/$max_retries] 访问：$url" >&2
        data=$(curl -L -s --compressed \
            -H "User-Agent: $HTTP_UA" \
            -H "Referer: $HTTP_REF" \
            --connect-timeout "$timeout" --max-time "$timeout" \
            "$url" 2>/dev/null)
        if [ -n "$data" ] && \
           [[ ! "$data" =~ "DOCTYPE html" ]] && \
           [[ ! "$data" =~ "Forbidden" ]] && \
           [[ ! "$data" =~ "error" ]] && \
           [[ ${#data} -gt 20 ]]; then
            echo "$data"; return 0
        fi
        if [ $i -lt $max_retries ]; then
            echo "  ⚠️ 第 $i 次失败，等待 ${retry_interval}s 后重试..." >&2
            sleep $retry_interval
        fi
    done
    echo "❌ 多次尝试后数据获取失败" >&2
    return 1
}

multi_source_fetch() {
    local sources=("$@")
    local max_retries_per_source=3
    local global_max_sources=5
    local total_sources=${#sources[@]}
    if [ $total_sources -gt $global_max_sources ]; then
        total_sources=$global_max_sources
    fi
    echo "🔄 开始从多个数据源获取（最多 $total_sources 个源，每源重试 $max_retries_per_source 次）..." >&2
    for ((idx=0; idx<total_sources; idx++)); do
        local url="${sources[$idx]}"
        echo "=== 尝试源 $((idx+1))/$total_sources: $url ===" >&2
        local data
        if data=$(curl_retry "$url" $max_retries_per_source 30); then
            echo "✅ 成功从源 $((idx+1)) 获取数据" >&2
            echo "$data"; return 0
        fi
    done
    echo "❌ 所有 $total_sources 个数据源均获取失败" >&2
    return 1
}
