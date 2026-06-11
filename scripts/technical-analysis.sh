#!/bin/bash
# 技术分析脚本（多源 + 重试 + 代码映射 + 无 bc 兼容）
# 用法：$0 <股票代码|shXXXXXX|szXXXXXX|secid>

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

echo "=========================================="
echo "📊 技术分析 - ${STOCK_CODE}"
echo ""
echo "⚙️ 数据源重试配置：最多 3 次"
echo "=========================================="

declare -a PRICE_URLS=(
    "http://qt.gtimg.cn/q=${prefix}"
    "https://push2.eastmoney.com/api/qt/stock/get?secid=${secid}&fields=f43,f44,f45,f46,f47"
)

data=""
success=false
for url in "${PRICE_URLS[@]}"; do
  echo "尝试数据源：${url%%\?*}..." >&2
  if fetched=$(curl_retry "$url" 3 20); then
    data="$fetched"; success=true; break
  fi
done

if [ "$success" = false ] || [ -z "$data" ]; then
  echo ""
  echo "❌ ❌ ❌ 所有数据源均无法获取行情数据"
  echo "已重试 3 次仍失败"
  exit 1
fi

# 数值计算函数（无 bc 时用 awk）
calc() { awk "BEGIN{print $*}"; }

CURRENT=""; PREV_CLOSE=""; OPEN=""; HIGH=""; LOW=""; VOLUME=""

if [[ "$data" =~ v_(sh|sz)[0-9]{6} ]]; then
  content=$(echo "$data" | sed -n 's/.*="\(.*\)";.*/\1/p')
  IFS='~' read -r -a f <<< "$content"
  CURRENT=${f[3]}
  PREV_CLOSE=${f[4]}
  OPEN=${f[5]}
  # 高低价位置在字符串后段（多次出现），取首次出现的高低（若不可得再尝试后段）
  HIGH=${f[33]}; LOW=${f[34]}
  if [[ -z "$HIGH" || -z "$LOW" ]]; then
    # 兜底：在 content 中查找形如 \\~[0-9]+\\.[0-9]+~ 的最大最小出现
    HIGH=$(echo "$content" | tr '~' '\n' | grep -E '^[0-9]+\.[0-9]+$' | sort -nr | head -1)
    LOW=$(echo "$content" | tr '~' '\n' | grep -E '^[0-9]+\.[0-9]+$' | sort -n | head -1)
  fi
  # 成交量字段在前段，兜底不强制
  VOLUME=${f[6]}
else
  # 东方财富 JSON（简单抓取）
  CURRENT=$(echo "$data" | grep -oE '"f43":-?[0-9]+\.?[0-9]*' | head -1 | awk -F: '{print $2}')
  PREV_CLOSE=$(echo "$data" | grep -oE '"f44":-?[0-9]+\.?[0-9]*' | head -1 | awk -F: '{print $2}')
  OPEN=$(echo "$data" | grep -oE '"f45":-?[0-9]+\.?[0-9]*' | head -1 | awk -F: '{print $2}')
  HIGH=$(echo "$data" | grep -oE '"f46":-?[0-9]+\.?[0-9]*' | head -1 | awk -F: '{print $2}')
  LOW=$(echo "$data" | grep -oE '"f47":-?[0-9]+\.?[0-9]*' | head -1 | awk -F: '{print $2}')
fi

echo ""
echo "=== 价格数据 ==="
[ -n "$CURRENT" ] && echo "当前价：$CURRENT 元" || echo "当前价：未获取到"
[ -n "$PREV_CLOSE" ] && echo "昨收：$PREV_CLOSE 元" || echo "昨收：未获取到"
[ -n "$OPEN" ] && echo "今开：$OPEN 元" || echo "今开：未获取到"
[ -n "$HIGH" ] && echo "最高：$HIGH 元" || echo "最高：未获取到"
[ -n "$LOW" ] && echo "最低：$LOW 元" || echo "最低：未获取到"
[ -n "$VOLUME" ] && echo "成交量：$VOLUME 手" || true

if [[ -n "$CURRENT" && -n "$PREV_CLOSE" ]]; then
  CHANGE=$(calc "$CURRENT - $PREV_CLOSE")
  CHANGE_PCT=$(calc "($CHANGE / $PREV_CLOSE) * 100")
  printf "涨跌：%.2f 元 (%.2f%%)\n" "$CHANGE" "$CHANGE_PCT"
fi

echo ""
echo "=== 技术指标（简版） ==="
if [[ -n "$HIGH" && -n "$LOW" ]]; then
  SUPPORT1=$(calc "$LOW * 0.98")
  SUPPORT2=$(calc "$LOW * 0.95")
  RESIST1=$(calc "$HIGH * 1.02")
  RESIST2=$(calc "$HIGH * 1.05")
  printf "支撑位 1: %.2f 元\n" "$SUPPORT1"
  printf "支撑位 2: %.2f 元\n" "$SUPPORT2"
  printf "阻力位 1: %.2f 元\n" "$RESIST1"
  printf "阻力位 2: %.2f 元\n" "$RESIST2"
  AMPLITUDE=$(calc "(($HIGH - $LOW) / $LOW) * 100")
  printf "振幅：%.2f%%\n" "$AMPLITUDE"
fi

echo ""
echo "=== 技术信号（简版） ==="
if [[ -n "$CURRENT" && -n "$PREV_CLOSE" ]]; then
  gt=$(awk -v a="$CURRENT" -v b="$PREV_CLOSE" 'BEGIN{if (a>b) print 1; else print 0}')
  if [[ "$gt" == "1" ]]; then
    echo "短期趋势：🟢 偏强"
  else
    echo "短期趋势：🔴 偏弱"
  fi
  if [[ -n "$HIGH" && -n "$LOW" ]]; then
    MID=$(calc "($HIGH + $LOW) / 2")
    gt2=$(awk -v a="$CURRENT" -v b="$MID" 'BEGIN{if (a>b) print 1; else print 0}')
    if [[ "$gt2" == "1" ]]; then
      echo "当日位置：上半区（偏强）"
    else
      echo "当日位置：下半区（偏弱）"
    fi
  fi
fi

echo ""
echo "=========================================="
echo "📝 注：行情来自多源（优先 EM，其次腾讯）；数值为脚本即时解析结果"
echo "=========================================="
