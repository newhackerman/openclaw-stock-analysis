#!/bin/bash
# K 线数据获取脚本（带重试 + 智能代码映射 + EM/Tencent 双源）
# 用法：./fetch-kline.sh <股票代码|shXXXXXX|szXXXXXX|secid> [周期] [bars]
# 周期：day(日线，默认), week(周线), month(月线)
# bars: 最近多少根（默认120）

STOCK_CODE=$1
PERIOD=${2:-day}
BARS=${3:-120}

if [ -z "$STOCK_CODE" ]; then
    echo "用法：$0 <股票代码> [周期] [bars]"
    echo "周期：day(默认), week, month"
    exit 1
fi

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/lib-retry.sh"
source "$SCRIPT_DIR/lib-stockcode.sh"

prefix=$(code_prefix "$STOCK_CODE")
secid=$(code_secid "$STOCK_CODE")

case $PERIOD in
    day|101)     KLT=101; TQ=day ;;
    week|102)    KLT=102; TQ=week;;
    month|103)   KLT=103; TQ=month;;
    *)           KLT=101; TQ=day ;;
esac

# 先尝试 EM（若可用能拿到更全字段），再回退腾讯
EM_URL="https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=${secid}&fields=f51,f52,f53,f54,f55,f56&klt=${KLT}&fqt=1&beg=0&end=99999999"
TX_URL="https://web.ifzq.gtimg.cn/appstock/app/kline/kline?param=${prefix},${TQ},,,-${BARS}"

echo "尝试 EM K线：${EM_URL%%\?*} (${TQ})" >&2
if data=$(curl_retry "$EM_URL" 3 20); then
  echo "✅ K 线数据获取成功（EM）"; echo "$data"; exit 0
fi

echo "尝试 腾讯 K线：${TX_URL%%\?*} (${TQ})" >&2
if data=$(curl_retry "$TX_URL" 3 20); then
  echo "✅ K 线数据获取成功（Tencent）"; echo "$data"; exit 0
fi

echo "❌ ❌ ❌ K 线数据获取失败（EM/Tencent 已重试 3 次）"; exit 1
