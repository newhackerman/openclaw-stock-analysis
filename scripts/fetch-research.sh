#!/bin/bash
# 券商研报获取脚本（带重试机制）
# 用法：./fetch-research.sh <股票代码> [券商名]

STOCK_CODE=$1
BROKER=${2:-all}

if [ -z "$STOCK_CODE" ]; then
    echo "用法：$0 <股票代码> [券商名]"
    exit 1
fi

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/lib-retry.sh"

echo "🔄 获取券商研报：$STOCK_CODE"

max_retries=3
timeout=30

# 券商列表
case $BROKER in
    "all")
        BROKERS=("中信证券" "中金公司" "天风证券" "华泰证券" "国泰君安")
        ;;
    *)
        BROKERS=("$BROKER")
        ;;
esac

success=false

for broker in "${BROKERS[@]}"; do
    echo ""
    echo "=== 尝试 ${broker} ===" >&2
    
    # 券商研报搜索 URL
    case $broker in
        "中信证券")
            URL="https://www.cs.ecitic.com/research?stockCode=${STOCK_CODE}"
            ;;
        "中金公司")
            URL="https://www.cicc.com/research?code=${STOCK_CODE}"
            ;;
        "天风证券")
            URL="https://www.tfzq.com/research/report?stock=${STOCK_CODE}"
            ;;
        "华泰证券")
            URL="https://www.htsc.com.cn/research?symbol=${STOCK_CODE}"
            ;;
        "国泰君安")
            URL="https://www.gtja.com/research/report?code=${STOCK_CODE}"
            ;;
        *)
            URL=""
            ;;
    esac
    
    if [ -n "$URL" ]; then
        echo "访问：${URL:0:60}..." >&2
        
        if data=$(curl_retry "$URL" $max_retries $timeout); then
            echo "✅ 成功获取 ${broker} 数据"
            echo "$data"
            success=true
        else
            echo "❌ ${broker} 数据获取失败（已重试 $max_retries 次）" >&2
        fi
    else
        echo "⚠️ 未知券商或无接口" >&2
    fi
done

if [ "$success" = false ]; then
    echo ""
    echo "⚠️ 所有券商数据获取失败或暂无可用数据"
    exit 0
fi
