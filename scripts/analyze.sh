#!/bin/bash
# 股票分析主脚本（带重试机制）
# 用法：$0 <股票代码> <公司名>

STOCK_CODE=$1
COMPANY_NAME=$2

if [ -z "$STOCK_CODE" ]; then
    echo "用法：$0 <股票代码> <公司名>"
    exit 1
fi

SCRIPT_DIR="$(dirname "$0")"
OUTPUT_DIR="/app/skills/stock-analysis/data/cache"
mkdir -p "$OUTPUT_DIR"

echo "=========================================="
echo "📈 股票投资分析 - $COMPANY_NAME ($STOCK_CODE)"
echo "=========================================="
echo ""
echo "⚙️ 配置：每数据源最大重试 3 次"
echo ""

success_count=0
total_steps=5

# 函数：记录成功次数
step_success() {
    success_count=$((success_count + 1))
}

# 步骤 1：获取行情数据
echo "[$((1))] 📊 获取行情数据..."
echo "----------------------------------------" >&2
"$SCRIPT_DIR/fetch-eastmoney.sh" "$STOCK_CODE" price > "$OUTPUT_DIR/price_${STOCK_CODE}.json" 2>&1
if [ $? -eq 0 ] && [ -s "$OUTPUT_DIR/price_${STOCK_CODE}.json" ]; then
    step_success
    echo "✅ 行情数据已保存"
else
    echo "❌ 行情数据获取失败"
fi

echo ""

# 步骤 2：获取财务数据
echo "[$((2))] 💰 获取财务数据..."
echo "----------------------------------------" >&2
"$SCRIPT_DIR/fetch-eastmoney.sh" "$STOCK_CODE" financial > "$OUTPUT_DIR/financial_${STOCK_CODE}.json" 2>&1
if [ $? -eq 0 ] && [ -s "$OUTPUT_DIR/financial_${STOCK_CODE}.json" ]; then
    step_success
    echo "✅ 财务数据已保存"
else
    echo "❌ 财务数据获取失败"
fi

echo ""

# 步骤 3：获取同花顺数据
echo "[$((3))] 📉 获取同花顺数据..."
echo "----------------------------------------" >&2
"$SCRIPT_DIR/fetch-ths.sh" "$STOCK_CODE" financial > "$OUTPUT_DIR/ths_${STOCK_CODE}.txt" 2>&1
if [ $? -eq 0 ] && [ -s "$OUTPUT_DIR/ths_${STOCK_CODE}.txt" ]; then
    step_success
    echo "✅ 同花顺数据已保存"
else
    echo "❌ 同花顺数据获取失败"
fi

echo ""

# 步骤 4：获取券商研报
echo "[$((4))] 📑 获取券商研报..."
echo "----------------------------------------" >&2
"$SCRIPT_DIR/fetch-research.sh" "$STOCK_CODE" all > "$OUTPUT_DIR/research_${STOCK_CODE}.txt" 2>&1
if [ $? -eq 0 ]; then
    step_success
    echo "✅ 券商研报已保存"
else
    echo "❌ 券商研报获取失败（可能暂无可用数据）"
fi

echo ""

# 步骤 5：获取持仓数据
echo "[$((5))] 🏦 获取持仓数据..."
echo "----------------------------------------" >&2
"$SCRIPT_DIR/fetch-eastmoney.sh" "$STOCK_CODE" holder > "$OUTPUT_DIR/holder_${STOCK_CODE}.json" 2>&1
if [ $? -eq 0 ] && [ -s "$OUTPUT_DIR/holder_${STOCK_CODE}.json" ]; then
    step_success
    echo "✅ 持仓数据已保存"
else
    echo "❌ 持仓数据获取失败"
fi

echo ""
echo "=========================================="
echo "📊 数据统计："
echo "  ✅ 成功：$success_count / $total_steps"
echo "  ❌ 失败：$((total_steps - success_count)) / $total_steps"
echo "=========================================="
echo ""

if [ $success_count -lt 2 ]; then
    echo "⚠️ ⚠️ ⚠️ 数据获取成功率低于 50%，建议检查网络或稍后重试" >&2
    exit 1
fi

echo "数据保存位置：$OUTPUT_DIR"
echo ""
echo "下一步：使用模板生成分析报告"
