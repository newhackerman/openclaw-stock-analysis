#!/bin/bash
# 财务数据获取脚本（东财主源 + Wind 预留 + 本地回退）
# 用法：./fetch-financials.sh <股票代码|shXXXXXX|szXXXXXX|secid>

code="$1"
if [ -z "$code" ]; then echo "用法：$0 <股票代码>"; exit 1; fi

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/lib-retry.sh"
source "$SCRIPT_DIR/lib-stockcode.sh"

pref=$(code_prefix "$code")
secid=$(code_secid "$code")
core="${pref#sh}"
core="${core#sz}"
market="SZ"
[[ "$pref" =~ ^sh ]] && market="SH"
windcode="${core}.${market}"

is_valid_financial_payload() {
  local data="$1"
  [ -n "$data" ] || return 1
  [[ ! "$data" =~ "DOCTYPE html" ]] || return 1
  [[ ! "$data" =~ "报表名称不能为空" ]] || return 1
  [[ "$data" =~ 'REPORT_DATE' ]] || [[ "$data" =~ 'NETPROFIT' ]] || [[ "$data" =~ 'TOTAL_OPERATE_INCOME' ]] || [[ "$data" =~ 'EPSJB' ]] || [[ "$data" =~ '净利润' ]] || return 0
  return 1
}

# 1) Eastmoney 主源：主要指标 + 三大财务报表接口
EM_URLS=(
  "https://emweb.securities.eastmoney.com/PC_HSF10/NewFinanceAnalysis/MainTargetAjax?type=${pref:0:2}&code=${core}"
  "https://datacenter.eastmoney.com/securities/api/data/v1/get?reportName=RPT_F10_FINANCE_GINCOME&columns=ALL&quoteColumns=&filter=(SECUCODE%3D%22${core}.${market}%22)&pageNumber=1&pageSize=5&sortTypes=-1&sortColumns=REPORT_DATE&source=HSF10&client=PC"
  "https://datacenter.eastmoney.com/securities/api/data/v1/get?reportName=RPT_F10_FINANCE_GBALANCE&columns=ALL&quoteColumns=&filter=(SECUCODE%3D%22${core}.${market}%22)&pageNumber=1&pageSize=5&sortTypes=-1&sortColumns=REPORT_DATE&source=HSF10&client=PC"
  "https://datacenter.eastmoney.com/securities/api/data/v1/get?reportName=RPT_F10_FINANCE_GCASHFLOW&columns=ALL&quoteColumns=&filter=(SECUCODE%3D%22${core}.${market}%22)&pageNumber=1&pageSize=5&sortTypes=-1&sortColumns=REPORT_DATE&source=HSF10&client=PC"
)

for url in "${EM_URLS[@]}"; do
  echo "尝试财务数据源：${url%%\?*}" >&2
  data=$(curl_retry "$url" 3 25) || true
  if is_valid_financial_payload "$data"; then
    echo "$data"
    exit 0
  fi
done

# 2) Wind 预留接口（若配置 WIND_API_URL / WIND_API_TOKEN 则启用）
if [ -n "$WIND_API_URL" ] && [ -n "$WIND_API_TOKEN" ]; then
  echo "尝试 Wind 财务接口" >&2
  wind_payload=$(printf '{"windcode":"%s","fields":["revenue","net_profit","eps","roe","gross_margin","asset_liability_ratio"]}' "$windcode")
  data=$(curl -s --compressed -H "Content-Type: application/json" -H "Authorization: Bearer $WIND_API_TOKEN" --connect-timeout 25 --max-time 25 -X POST "$WIND_API_URL" -d "$wind_payload" 2>/dev/null) || true
  if [ -n "$data" ] && [[ ! "$data" =~ "DOCTYPE html" ]] && [[ ${#data} -gt 30 ]]; then
    echo "$data"
    exit 0
  fi
fi

# 3) AkShare 本地回退
AK_PY="/home/node/.openclaw/workspace/miniforge/envs/akenv/bin/python"
AK_SCRIPT="/home/node/.openclaw/workspace/skills/tencent-quotes-lite/scripts/get-ak-financials.py"
if [ -x "$AK_PY" ] && [ -f "$AK_SCRIPT" ]; then
  echo "尝试 AkShare 回退（本地）" >&2
  out=$("$AK_PY" "$AK_SCRIPT" "$pref" 2>/dev/null)
  if [ -n "$out" ] && [ ${#out} -gt 10 ]; then echo "$out"; exit 0; fi
fi

echo "{}"
exit 1
