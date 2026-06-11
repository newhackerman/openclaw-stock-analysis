#!/bin/bash
# 同花顺数据获取脚本（带重试机制）
# 用法：./fetch-ths.sh <股票代码> [数据类型]

STOCK_CODE=$1
DATA_TYPE=${2:-financial}

if [ -z "$STOCK_CODE" ]; then
    echo "用法：$0 <股票代码> [数据类型]"
    exit 1
fi

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/lib-retry.sh"

echo "🔄 获取同花顺数据：$STOCK_CODE ($DATA_TYPE)"

max_retries=3
timeout=30

case $DATA_TYPE in
    "financial")
        # 同花顺财务数据接口
        URL="https://data.10jqka.com.cn/financemodel/fina/newfina/index?code=${STOCK_CODE}"
        
        if data=$(curl_retry "$URL" $max_retries $timeout); then
            echo "✅ 同花顺财务数据获取成功"
            echo "$data"
        else
            echo "❌ 同花顺财务数据获取失败（已重试 $max_retries 次）"
            exit 1
        fi
        ;;
        
    "price")
        # 同花顺实时行情
        URL="http://poll.10jqka.com.cn/f10/cn600879/realtime"
        
        if data=$(curl_retry "$URL" $max_retries $timeout); then
            echo "✅ 同花顺实时行情获取成功"
            echo "$data"
        else
            echo "❌ 同花顺实时行情获取失败（已重试 $max_retries 次）"
            exit 1
        fi
        ;;
        
    *)
        echo "未知的数据类型：$DATA_TYPE"
        exit 1
        ;;
esac
