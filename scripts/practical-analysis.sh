#!/bin/bash
# 实战版股票分析入口：自动抓取价格/财务，输出 Markdown 报告
# 用法：./practical-analysis.sh <股票代码> <公司名> [同行代码1 同行代码2]

set -e

STOCK_CODE="$1"
COMPANY_NAME="$2"
PEER1="${3:-002460}"
PEER2="${4:-000792}"

if [ -z "$STOCK_CODE" ] || [ -z "$COMPANY_NAME" ]; then
  echo "用法：$0 <股票代码> <公司名> [同行代码1 同行代码2]"
  exit 1
fi

SCRIPT_DIR="$(dirname "$0")"
OUT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/data/reports"
TMP_DIR="$(mktemp -d)"
mkdir -p "$OUT_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

normalize_name() {
  case "$1" in
    002466) echo "天齐锂业" ;;
    002460) echo "赣锋锂业" ;;
    000792) echo "盐湖股份" ;;
    *) echo "$1" ;;
  esac
}

extract_price_line() {
  local code="$1"
  local pref="sz${code}"
  [[ "$code" =~ ^6 ]] && pref="sh${code}"
  curl -s "http://qt.gtimg.cn/q=${pref}" 2>/dev/null || true
}

extract_price_field() {
  local raw="$1"
  local idx="$2"
  python3 - "$raw" "$idx" <<'PY'
import sys
raw=sys.argv[1]
idx=int(sys.argv[2])
parts=raw.split('~')
print(parts[idx] if len(parts)>idx else '')
PY
}

extract_financial_json() {
  local code="$1"
  bash "$SCRIPT_DIR/fetch-financials.sh" "$code" 2>/dev/null > "$TMP_DIR/fin_${code}.json" || true
  cat "$TMP_DIR/fin_${code}.json"
}

extract_fin_metric() {
  local file="$1"
  local metric="$2"
  python3 - "$file" "$metric" <<'PY'
import json,sys
path,metric=sys.argv[1],sys.argv[2]
try:
    text=open(path,'r',encoding='utf-8',errors='ignore').read().strip()
    if not text:
        print('N/A'); raise SystemExit
    data=json.loads(text)
except Exception:
    print('N/A'); raise SystemExit

if isinstance(data, dict) and 'abstract' in data and isinstance(data['abstract'], list):
    rows=data['abstract']
    target={'revenue':'营业总收入','net_profit':'归母净利润','roe':'净资产收益率','gross_margin':'销售毛利率'}.get(metric)
    if target:
        for row in rows:
            if row.get('指标')==target:
                keys=[k for k in row.keys() if k.isdigit() or (len(k)==8 and k.isdigit())]
                keys=sorted(keys, reverse=True)
                for k in keys:
                    v=row.get(k)
                    if v not in [None,'', 'nan']:
                        print(v)
                        raise SystemExit
for key in ['result','Result','data','Data']:
    if isinstance(data, dict) and key in data:
        val=data[key]
        if isinstance(val, dict):
            arr=val.get('data') or val.get('Data') or []
        else:
            arr=val if isinstance(val,list) else []
        if arr:
            row=arr[0]
            mapping={
              'revenue':['TOTAL_OPERATE_INCOME','OPERATE_INCOME','营业总收入'],
              'net_profit':['NETPROFIT','PARENT_NETPROFIT','归母净利润'],
              'roe':['ROEJQ','ROEWEIGHT','净资产收益率'],
              'gross_margin':['XSMLL','销售毛利率']
            }
            for cand in mapping.get(metric,[]):
                if cand in row and row[cand] not in [None,'']:
                    print(row[cand])
                    raise SystemExit
print('N/A')
PY
}

gen_block() {
  local code="$1"
  local name="$2"
  local role="$3"
  local raw
  raw=$(extract_price_line "$code")
  local price prev open high low change_pct mktcap pe
  price=$(extract_price_field "$raw" 3)
  prev=$(extract_price_field "$raw" 4)
  open=$(extract_price_field "$raw" 5)
  high=$(extract_price_field "$raw" 33)
  low=$(extract_price_field "$raw" 34)
  change_pct=$(extract_price_field "$raw" 32)
  mktcap=$(extract_price_field "$raw" 45)
  pe=$(extract_price_field "$raw" 39)

  bash "$SCRIPT_DIR/technical-analysis.sh" "$code" > "$TMP_DIR/tech_${code}.txt" 2>/dev/null || true
  support=$(grep '支撑位 1:' "$TMP_DIR/tech_${code}.txt" | awk '{print $3}')
  resistance=$(grep '阻力位 1:' "$TMP_DIR/tech_${code}.txt" | awk '{print $3}')
  trend=$(grep '短期趋势：' "$TMP_DIR/tech_${code}.txt" | sed 's/.*短期趋势：//')

  extract_financial_json "$code" >/dev/null
  revenue=$(extract_fin_metric "$TMP_DIR/fin_${code}.json" revenue)
  net_profit=$(extract_fin_metric "$TMP_DIR/fin_${code}.json" net_profit)
  roe=$(extract_fin_metric "$TMP_DIR/fin_${code}.json" roe)
  gross_margin=$(extract_fin_metric "$TMP_DIR/fin_${code}.json" gross_margin)

  cat > "$TMP_DIR/block_${role}_${code}.json" <<JSON
{"role":"$role","code":"$code","name":"$name","price":"$price","prev":"$prev","open":"$open","high":"$high","low":"$low","change_pct":"$change_pct","mktcap":"$mktcap","pe":"$pe","support":"$support","resistance":"$resistance","trend":"$trend","revenue":"$revenue","net_profit":"$net_profit","roe":"$roe","gross_margin":"$gross_margin"}
JSON
}

gen_block "$STOCK_CODE" "$COMPANY_NAME" main
gen_block "$PEER1" "$(normalize_name "$PEER1")" peer1
gen_block "$PEER2" "$(normalize_name "$PEER2")" peer2

REPORT="$OUT_DIR/${STOCK_CODE}_$(date +%F).md"
python3 - "$TMP_DIR" "$REPORT" <<'PY'
import json,sys,datetime
from pathlib import Path

tmp=Path(sys.argv[1])
out=Path(sys.argv[2])
main=json.loads((tmp/'block_main_002466.json').read_text()) if (tmp/'block_main_002466.json').exists() else None
if main is None:
    for p in tmp.glob('block_main_*.json'):
        main=json.loads(p.read_text())
        break
peers=[json.loads(p.read_text()) for p in sorted(tmp.glob('block_peer*.json'))]
blocks=[main]+peers

def fnum(v):
    try: return float(str(v).replace('%',''))
    except: return None

def score(b):
    s=0
    cp=fnum(b.get('change_pct'))
    if cp is not None: s += min(max(cp,0),10)*2
    pe=fnum(b.get('pe'))
    if pe and pe>0: s += max(0,30-min(pe,60))/2
    if '偏强' in (b.get('trend') or ''): s += 15
    for k in ['roe','gross_margin']:
        v=fnum(b.get(k))
        if v is not None: s += min(max(v,0),30)/3
    return round(s,1)

for b in blocks: b['score']=score(b)
ranked=sorted(blocks,key=lambda x:x['score'], reverse=True)
leader=ranked[0]
core_conclusion = '行业内优先关注' if leader['code']==main['code'] else f"同行中更优先关注 {leader['name']}"

def line(s=''): return s+'\n'
md=''
md+=line(f"# {main['name']}（{main['code']}）实战分析报告")
md+=line()
md+=line(f"**分析日期：** {datetime.date.today()}  ")
md+=line(f"**当前股价：** {main.get('price','N/A')} 元  ")
md+=line(f"**核心结论：** {core_conclusion}")
md+=line()
md+=line('---')
md+=line()
md+=line('## 一、核心观点')
md+=line()
md+=line(f"> {main['name']} 属于锂资源高弹性标的，当前短期趋势为 **{main.get('trend','N/A')}**，更适合结合锂价周期与板块情绪做中短期跟踪。")
if leader['code'] != main['code']:
    md+=line(f"> 同行业对比中，**{leader['name']}** 综合分更高，当前性价比/强势度更突出。")
md+=line()
md+=line('## 二、个股概览')
md+=line()
md+=line('| 项目 | 数据 |')
md+=line('|---|---:|')
for k,v in [('当前价',main.get('price','N/A')),('涨跌幅',str(main.get('change_pct','N/A'))+'%'),('最高',main.get('high','N/A')),('最低',main.get('low','N/A')),('PE(脚本解析)',main.get('pe','N/A')),('总市值(脚本解析)',main.get('mktcap','N/A')),('支撑位',main.get('support','N/A')),('阻力位',main.get('resistance','N/A')),('短期趋势',main.get('trend','N/A')),('营业总收入(最新抓取)',main.get('revenue','N/A')),('归母净利润(最新抓取)',main.get('net_profit','N/A')),('ROE(最新抓取)',main.get('roe','N/A')),('毛利率(最新抓取)',main.get('gross_margin','N/A'))]:
    md+=line(f'| {k} | {v} |')
md+=line()
md+=line('## 三、同行业对比')
md+=line()
md+=line('| 公司 | 代码 | 现价 | 涨跌幅 | PE | ROE | 毛利率 | 趋势 | 综合分 |')
md+=line('|---|---|---:|---:|---:|---:|---:|---|---:|')
for b in ranked:
    md+=line(f"| {b['name']} | {b['code']} | {b.get('price','N/A')} | {b.get('change_pct','N/A')}% | {b.get('pe','N/A')} | {b.get('roe','N/A')} | {b.get('gross_margin','N/A')} | {b.get('trend','N/A')} | {b.get('score','N/A')} |")
md+=line()
md+=line('## 四、排名与判断')
md+=line()
for i,b in enumerate(ranked,1):
    md+=line(f"{i}. **{b['name']}**：综合分 {b['score']}")
md+=line()
md+=line('### 结论解读')
md+=line()
md+=line(f"- **首选标的：** {leader['name']}")
md+=line(f"- **当前分析对象：** {main['name']}")
md+=line(f"- **是否行业首选：** {'是' if leader['code']==main['code'] else '否'}")
md+=line()
md+=line('## 五、操作建议')
md+=line()
md+=line(f"- 若偏短线：关注 **{main.get('resistance','N/A')} 元** 附近突破情况。")
md+=line(f"- 若偏波段：等待回踩 **{main.get('support','N/A')} 元** 一带的承接。")
md+=line('- 若偏稳健：优先比较同行综合分更高的标的，不建议仅因单日大涨追高。')
md+=line()
md+=line('## 六、风险提示')
md+=line()
md+=line('- 锂价波动导致业绩预期变化')
md+=line('- 周期股估值波动大')
md+=line('- 板块情绪回落可能造成高波动回撤')
md+=line()
md+=line('---')
md+=line()
md+=line('*说明：本报告由实战版脚本自动生成，财务数据优先取东方财富，失败时回退本地源；仅供参考，不构成投资建议。*')
out.write_text(md, encoding='utf-8')
print(out)
PY

echo "$REPORT"
