#!/bin/bash
# 东方财富数据获取脚本（带重试 + 智能代码映射 + 响应有效性校验）
# 用法：./fetch-eastmoney.sh <股票代码|shXXXXXX|szXXXXXX|secid> [数据类型]
# 数据类型：price(行情), financial(财务), holder(持仓)

STOCK_CODE=$1
DATA_TYPE=${2:-price}

if [ -z "$STOCK_CODE" ]; then
    echo "用法：$0 <股票代码> [数据类型]"
    echo "数据类型：price(默认), financial, holder"
    exit 1
fi

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/lib-retry.sh"
source "$SCRIPT_DIR/lib-stockcode.sh"

prefix=$(code_prefix "$STOCK_CODE")
secid=$(code_secid "$STOCK_CODE")
core_code="${prefix#sh}"
core_code="${core_code#sz}"

MAX_RETRIES=3
TIMEOUT=20

echo "🔄 获取${DATA_TYPE}数据：$STOCK_CODE → secid=${secid} (最大重试 ${MAX_RETRIES} 次)" >&2

is_valid_price_response() {
  local data="$1"
  [ -n "$data" ] || return 1
  [[ "$data" =~ \"data\" ]] || [[ "$data" =~ ^v_ ]] || return 1
  [[ ! "$data" =~ "DOCTYPE html" ]] || return 1
  return 0
}

is_valid_financial_response() {
  local data="$1"
  [ -n "$data" ] || return 1
  [[ ! "$data" =~ "DOCTYPE html" ]] || return 1
  [[ ! "$data" =~ "报表名称不能为空" ]] || return 1
  [[ ! "$data" =~ '"success":false' ]] || [[ "$data" =~ '"result"' ]] || [[ "$data" =~ '"data"' ]] || [[ "$data" =~ 'REPORT_DATE' ]] || return 1
  [[ "$data" =~ 'REPORT_DATE' ]] || [[ "$data" =~ 'NETPROFIT' ]] || [[ "$data" =~ 'TOTAL_OPERATE_INCOME' ]] || [[ "$data" =~ 'EPSJB' ]] || [[ "$data" =~ 'RESULT' ]] || [[ "$data" =~ 'result' ]] || return 1
  return 0
}

is_valid_holder_response() {
  local data="$1"
  [ -n "$data" ] || return 1
  [[ ! "$data" =~ "DOCTYPE html" ]] || return 1
  [[ "$data" =~ '股东' ]] || [[ "$data" =~ 'HOLDER' ]] || [[ "$data" =~ 'SECURITY_CODE' ]] || [[ "$data" =~ 'data' ]] || return 0
  return 1
}

fetch_first_valid() {
  local validator="$1"
  shift
  local urls=("$@")
  local data=""
  for url in "${urls[@]}"; do
    echo "尝试数据源：$url" >&2
    data=$(curl_retry "$url" $MAX_RETRIES $TIMEOUT) || true
    if "$validator" "$data"; then
      echo "$data"
      return 0
    fi
    echo "❌ 该源返回无效响应，继续尝试下一个..." >&2
  done
  return 1
}

case $DATA_TYPE in
  "price")
    declare -a URLS=(
      "https://push2.eastmoney.com/api/qt/stock/get?fltt=2&invt=2&secid=${secid}&fields=f57,f58,f43,f44,f45,f46,f47,f48,f49,f50,f51,f52,f60,f116,f117"
      "https://push2.eastmoney.com/api/qt/stock/get?secid=${secid}"
    )
    if data=$(fetch_first_valid is_valid_price_response "${URLS[@]}"); then
      echo "✅ 数据获取成功" >&2
      echo "$data"
    else
      echo "❌ 行情数据获取失败（已重试 $MAX_RETRIES 次）" >&2
      exit 1
    fi
    ;;
  "financial")
    # 东方财富较稳定的 F10/财报接口：主要指标 + 利润表 + 资产负债表 + 现金流量表
    declare -a FINANCIAL_URLS=(
      "https://datacenter.eastmoney.com/securities/api/data/v1/get?reportName=RPT_F10_FINANCE_GINCOME&columns=ALL&quoteColumns=&filter=(SECUCODE%3D%22${core_code}.${prefix:0:2^^}%22)&pageNumber=1&pageSize=5&sortTypes=-1&sortColumns=REPORT_DATE&source=HSF10&client=PC&v=05801539214834999"
      "https://datacenter.eastmoney.com/securities/api/data/v1/get?reportName=RPT_F10_FINANCE_GCASHFLOW&columns=ALL&quoteColumns=&filter=(SECUCODE%3D%22${core_code}.${prefix:0:2^^}%22)&pageNumber=1&pageSize=5&sortTypes=-1&sortColumns=REPORT_DATE&source=HSF10&client=PC&v=05801539214834999"
      "https://datacenter.eastmoney.com/securities/api/data/v1/get?reportName=RPT_F10_FINANCE_GBALANCE&columns=ALL&quoteColumns=&filter=(SECUCODE%3D%22${core_code}.${prefix:0:2^^}%22)&pageNumber=1&pageSize=5&sortTypes=-1&sortColumns=REPORT_DATE&source=HSF10&client=PC&v=05801539214834999"
      "https://emweb.securities.eastmoney.com/PC_HSF10/NewFinanceAnalysis/MainTargetAjax?type=${prefix:0:2}&code=${core_code}"
    )
    if data=$(fetch_first_valid is_valid_financial_response "${FINANCIAL_URLS[@]}"); then
      echo "✅ 财务数据获取成功" >&2
      echo "$data"
    else
      echo "❌ 财务数据获取失败（所有数据源已重试 $MAX_RETRIES 次）" >&2
      exit 1
    fi
    ;;
  "holder")
    declare -a HOLDER_URLS=(
      "https://datacenter.eastmoney.com/securities/api/data/v1/get?reportName=RPT_F10_EH_HOLDERNUM&columns=ALL&filter=(SECURITY_CODE%3D%22${core_code}%22)&pageNumber=1&pageSize=10&sortTypes=-1&sortColumns=END_DATE&source=HSF10&client=PC"
      "https://datacenter-web.eastmoney.com/api/data/v1/get?reportName=RPT_F10_EH_FREEHOLDERS&columns=ALL&filter=(SECURITY_CODE%3D%22${core_code}%22)&pageNumber=1&pageSize=10&sortTypes=-1&sortColumns=END_DATE&source=HSF10&client=PC"
    )
    if data=$(fetch_first_valid is_valid_holder_response "${HOLDER_URLS[@]}"); then
      echo "✅ 股东持仓数据获取成功" >&2
      echo "$data"
    else
      echo "❌ 股东持仓数据获取失败（已重试 $MAX_RETRIES 次）" >&2
      exit 1
    fi
    ;;
  *)
    echo "未知的数据类型：$DATA_TYPE" >&2
    exit 1
    ;;
esac
