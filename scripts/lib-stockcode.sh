#!/bin/bash
# 股票代码工具库：将6位代码映射为交易所前缀与 secid，并生成第三方符号
# 使用：
#   code_prefix 600879     → sh600879 / sz000001
#   code_secid  600879     → 1.600879 / 0.000001
#   code_yahoo  600879     → 600879.SS / 000001.SZ

is_sh_code() { local c="$1"; [[ "$c" =~ ^6[0-9]{5}$ ]] || [[ "$c" =~ ^sh[0-9]{6}$ ]]; }
is_sz_code() { local c="$1"; [[ "$c" =~ ^(0|3)[0-9]{5}$ ]] || [[ "$c" =~ ^sz[0-9]{6}$ ]]; }

# 规范化为 shXXXXXX / szXXXXXX
code_prefix() {
  local code="$1"
  # secid → 前缀
  if [[ "$code" =~ ^[01]\.[0-9]{6}$ ]]; then
    local core="${code#*.}"; [[ "$code" =~ ^1\. ]] && echo "sh$core" || echo "sz$core"; return 0
  fi
  # 已带前缀
  if [[ "$code" =~ ^(sh|sz)[0-9]{6}$ ]]; then echo "$code"; return 0; fi
  # 仅 6 位
  if [[ "$code" =~ ^[0-9]{6}$ ]]; then [[ "$code" =~ ^6 ]] && echo "sh$code" || echo "sz$code"; return 0; fi
  echo "$code"
}

# Eastmoney secid：上交所=1.，深交所=0.
code_secid() {
  local pref; pref=$(code_prefix "$1"); local core="${pref#sh}"; core="${core#sz}"
  [[ "$pref" =~ ^sh ]] && echo "1.$core" || echo "0.$core"
}

# Yahoo Finance 符号：上交所 .SS，深交所 .SZ
code_yahoo() {
  local pref; pref=$(code_prefix "$1"); local core="${pref#sh}"; core="${core#sz}"
  [[ "$pref" =~ ^sh ]] && echo "${core}.SS" || echo "${core}.SZ"
}
