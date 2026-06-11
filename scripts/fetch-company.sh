#!/bin/bash
# 公司基本信息获取脚本（带重试机制）
# 用法：./fetch-company.sh <股票代码>

STOCK_CODE=$1

if [ -z "$STOCK_CODE" ]; then
    echo "用法：$0 <股票代码>"
    exit 1
fi

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/lib-retry.sh"

echo "🔄 获取公司信息：$STOCK_CODE"

max_retries=3
timeout=30

# 多个公司信息接口
declare -a COMPANY_URLS=(
    "https://push2.eastmoney.com/api/qt/get?secid=1.${STOCK_CODE}&fields=f58,f46,f47,f61,f62,f73"
    "https://datacenter-web.eastmoney.com/api/data/v1/get?code=${STOCK_CODE}"
)

success=false

for url in "${COMPANY_URLS[@]}"; do
    echo ""
    echo "尝试：${url:0:70}..." >&2
    
    if data=$(curl_retry "$url" $max_retries $timeout); then
        echo "✅ 公司信息获取成功"
        
        if command -v jq &> /dev/null; then
            echo "$data" | jq '.' 2>/dev/null || echo "$data"
        else
            echo "$data"
        fi
        success=true
        break
    else
        echo "❌ 该源获取失败，继续尝试下一个..." >&2
    fi
done

if [ "$success" = false ]; then
    echo ""
    echo "⚠️ 所有公司信息数据源获取失败（已重试 $max_retries 次）"
    exit 1
fi
