#!/bin/bash
# 股票价格获取脚本（多数据源 + 重试 + Yahoo 兜底）
# 用法：./fetch-price.sh <股票代码|shXXXXXX|szXXXXXX|secid>

STOCK_CODE=$1

if [ -z "$STOCK_CODE" ]; then
    echo "用法：$0 <股票代码>"
    exit 1
fi

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/lib-retry.sh"
source "$SCRIPT_DIR/lib-stockcode.sh"

prefix=$(code_prefix "$STOCK_CODE")
secid=$(code_secid "$STOCK_CODE")
yahoo=$(code_yahoo "$STOCK_CODE")

echo "=== 获取股价：$STOCK_CODE ==="
echo "规范化：prefix=$prefix secid=$secid yahoo=$yahoo" >&2

# 定义多个数据源 URL（按优先级）
EM_URL="https://push2.eastmoney.com/api/qt/stock/get?fltt=2&invt=2&secid=${secid}&fields=f57,f58,f43,f44,f45,f46,f60,f47,f48,f49,f50,f51,f52"
TX_URL="http://qt.gtimg.cn/q=${prefix}"
SINA_URL="http://hq.sinajs.cn/list=${prefix}"
YF_URL="https://query1.finance.yahoo.com/v10/finance/quoteSummary/${yahoo}?modules=price,summaryDetail"

for src in EM TX SINA YF; do
  case $src in
    EM)  url="$EM_URL";   tag="东方财富";;
    TX)  url="$TX_URL";   tag="腾讯财经";;
    SINA)url="$SINA_URL"; tag="新浪财经";;
    YF)  url="$YF_URL";   tag="Yahoo";;
  esac
  echo "--- 尝试：$tag (${url%%\?*}) ---" >&2
  data=$(curl_retry "$url" 3 20)
  if [ $? -eq 0 ] && [ -n "$data" ]; then
    echo "✅ 成功获取 $tag 数据"
    echo "$data"
    exit 0
  fi
done

echo "❌ 所有数据源获取失败（已含 Yahoo 兜底，3 次重试/源）"
exit 1
