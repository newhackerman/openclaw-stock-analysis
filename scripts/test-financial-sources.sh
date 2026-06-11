#!/bin/bash
# 财务数据源稳定性测试脚本
# 用法：./test-financial-sources.sh <股票代码> [轮次]

code="$1"
rounds="${2:-3}"
if [ -z "$code" ]; then
  echo "用法：$0 <股票代码> [轮次]"
  exit 1
fi

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/lib-stockcode.sh"

pref=$(code_prefix "$code")
core="${pref#sh}"
core="${core#sz}"
market="SZ"
[[ "$pref" =~ ^sh ]] && market="SH"

urls=(
  "EM_MAINTARGET|https://emweb.securities.eastmoney.com/PC_HSF10/NewFinanceAnalysis/MainTargetAjax?type=${pref:0:2}&code=${core}"
  "EM_INCOME|https://datacenter.eastmoney.com/securities/api/data/v1/get?reportName=RPT_F10_FINANCE_GINCOME&columns=ALL&quoteColumns=&filter=(SECUCODE%3D%22${core}.${market}%22)&pageNumber=1&pageSize=5&sortTypes=-1&sortColumns=REPORT_DATE&source=HSF10&client=PC"
  "EM_BALANCE|https://datacenter.eastmoney.com/securities/api/data/v1/get?reportName=RPT_F10_FINANCE_GBALANCE&columns=ALL&quoteColumns=&filter=(SECUCODE%3D%22${core}.${market}%22)&pageNumber=1&pageSize=5&sortTypes=-1&sortColumns=REPORT_DATE&source=HSF10&client=PC"
  "EM_CASHFLOW|https://datacenter.eastmoney.com/securities/api/data/v1/get?reportName=RPT_F10_FINANCE_GCASHFLOW&columns=ALL&quoteColumns=&filter=(SECUCODE%3D%22${core}.${market}%22)&pageNumber=1&pageSize=5&sortTypes=-1&sortColumns=REPORT_DATE&source=HSF10&client=PC"
)

printf "# Financial Source Stability Test\n"
printf "code=%s rounds=%s\n\n" "$code" "$rounds"
printf "| Source | Success | Fail | Notes |\n"
printf "|---|---:|---:|---|\n"

for item in "${urls[@]}"; do
  name="${item%%|*}"
  url="${item#*|}"
  ok=0
  fail=0
  for i in $(seq 1 "$rounds"); do
    data=$(curl -s --compressed -H 'User-Agent: Mozilla/5.0' -H 'Referer: https://quote.eastmoney.com/' --connect-timeout 20 --max-time 20 "$url" 2>/dev/null) || true
    if [ -n "$data" ] && [[ ! "$data" =~ "DOCTYPE html" ]] && [[ ! "$data" =~ "报表名称不能为空" ]] && [[ ${#data} -gt 50 ]]; then
      ok=$((ok+1))
    else
      fail=$((fail+1))
    fi
  done
  notes="usable"
  [ "$ok" -eq 0 ] && notes="unstable/unusable"
  printf "| %s | %s | %s | %s |\n" "$name" "$ok" "$fail" "$notes"
done

if [ -n "$WIND_API_URL" ] && [ -n "$WIND_API_TOKEN" ]; then
  ok=0; fail=0
  for i in $(seq 1 "$rounds"); do
    payload=$(printf '{"windcode":"%s.%s","fields":["revenue","net_profit","eps"]}' "$core" "$market")
    data=$(curl -s --compressed -H 'Content-Type: application/json' -H "Authorization: Bearer $WIND_API_TOKEN" --connect-timeout 20 --max-time 20 -X POST "$WIND_API_URL" -d "$payload" 2>/dev/null) || true
    if [ -n "$data" ] && [[ ! "$data" =~ "DOCTYPE html" ]] && [[ ${#data} -gt 30 ]]; then ok=$((ok+1)); else fail=$((fail+1)); fi
  done
  notes="configured"
  [ "$ok" -eq 0 ] && notes="configured but unusable"
  printf "| %s | %s | %s | %s |\n" "WIND_API" "$ok" "$fail" "$notes"
else
  printf "| %s | %s | %s | %s |\n" "WIND_API" "0" "0" "not configured" 
fi
