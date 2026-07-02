#!/usr/bin/env bash
set -e

SING_BOX_VERSION="${SING_BOX_VERSION:-${VERSION:-1.13.14}}"
SING_BOX_VERSION="${SING_BOX_VERSION#v}"
LOCAL_PORT="${LOCAL_PORT:-10808}"
CONFIG_PATH="/etc/sing-box/config.json"
LOG_PATH="/var/log/sing-box.log"
PID_PATH="/tmp/sing-box.pid"
SING_BOX_DEB_PATH=""

echo_step() {
  echo
  echo "==> $*"
}

die() {
  echo "错误: $*" >&2
  exit 1
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    die "请使用 sudo 或 root 执行本脚本"
  fi
}

validate_local_port() {
  if [[ ! "${LOCAL_PORT}" =~ ^[0-9]+$ ]]; then
    die "LOCAL_PORT 必须是数字，当前值: ${LOCAL_PORT}"
  fi

  if (( LOCAL_PORT < 1 || LOCAL_PORT > 65535 )); then
    die "LOCAL_PORT 必须在 1 到 65535 之间，当前值: ${LOCAL_PORT}"
  fi
}

is_debian_like() {
  (
    if [[ ! -r /etc/os-release ]]; then
      exit 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release
    case " ${ID:-} ${ID_LIKE:-} " in
      *" debian "*|*" ubuntu "*)
        exit 0
        ;;
      *)
        exit 1
        ;;
    esac
  )
}

apt_install_with_timeout() {
  timeout 60s apt-get install -y \
    -o DPkg::Lock::Timeout=120 \
    -o Acquire::http::Timeout=10 \
    -o Acquire::https::Timeout=10 \
    -o Acquire::Retries=0 \
    "$@"
}

ensure_curl() {
  if command -v curl >/dev/null 2>&1; then
    return 0
  fi

  echo_step "未找到 curl，尝试安装 curl 和 ca-certificates"
  apt_install_with_timeout curl ca-certificates || die "自动安装 curl 失败。请手动安装 curl ca-certificates 后重试"
}

detect_arch() {
  local deb_arch
  deb_arch="$(dpkg --print-architecture)"

  case "${deb_arch}" in
    amd64|arm64|i386|armhf|armel)
      echo "${deb_arch}"
      ;;
    *)
      die "不支持的系统架构: ${deb_arch}"
      ;;
  esac
}

download_sing_box_deb() {
  local arch pkg tmp_pkg proxy_url direct_url
  arch="$(detect_arch)"
  pkg="sing-box_${SING_BOX_VERSION}_linux_${arch}.deb"
  tmp_pkg="/tmp/${pkg}"
  proxy_url="https://gh-proxy.com/https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/${pkg}"
  direct_url="https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/${pkg}"

  if [[ -s "${tmp_pkg}" ]]; then
    echo_step "检测到 ${tmp_pkg} 已存在且非空，跳过下载"
  else
    echo_step "下载 sing-box ${SING_BOX_VERSION} (${arch})"
    if ! curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 180 -o "${tmp_pkg}" "${proxy_url}"; then
      echo "GitHub 代理下载失败，尝试直连 GitHub..."
      curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 180 -o "${tmp_pkg}" "${direct_url}" \
        || die "下载 sing-box deb 包失败，请检查网络或 SING_BOX_VERSION=${SING_BOX_VERSION} 是否存在"
    fi
  fi

  echo_step "验证 deb 包"
  ls -lh "${tmp_pkg}"
  dpkg-deb -I "${tmp_pkg}" >/dev/null || die "deb 包校验失败，请删除 ${tmp_pkg} 后重试"
  test -s "${tmp_pkg}" || die "deb 包为空，请删除 ${tmp_pkg} 后重试"

  SING_BOX_DEB_PATH="${tmp_pkg}"
}

install_sing_box() {
  if [[ "${SKIP_SING_BOX_DEB_INSTALL:-0}" == "1" ]]; then
    echo_step "已设置 SKIP_SING_BOX_DEB_INSTALL=1，跳过 deb 安装"
    command -v sing-box >/dev/null 2>&1 || die "未找到 sing-box，请先手动安装 sing-box"
    sing-box version
    return 0
  fi

  is_debian_like || die "install.sh 主要支持 Ubuntu / Debian。其他 Linux 请使用 install-linux.sh"
  command -v apt-get >/dev/null 2>&1 || die "未找到 apt-get，无法自动安装依赖"
  command -v apt >/dev/null 2>&1 || die "未找到 apt，无法安装本地 deb 包"
  command -v dpkg >/dev/null 2>&1 || die "未找到 dpkg，无法识别架构"
  command -v dpkg-deb >/dev/null 2>&1 || die "未找到 dpkg-deb，无法验证 deb 包"

  ensure_curl

  local tmp_pkg
  download_sing_box_deb
  tmp_pkg="${SING_BOX_DEB_PATH}"

  echo_step "安装 sing-box deb 包"
  timeout 120s apt install -y \
    -o DPkg::Lock::Timeout=120 \
    -o Acquire::http::Timeout=10 \
    -o Acquire::https::Timeout=10 \
    -o Acquire::Retries=0 \
    "${tmp_pkg}" || die "apt 安装 sing-box deb 包失败"

  echo_step "sing-box 版本"
  sing-box version
}

fallback_url_decode() {
  local encoded="${1//+/ }"
  printf '%b' "${encoded//%/\\x}"
}

fallback_parse_vless_url() {
  if [[ -z "${VLESS_URL:-}" ]]; then
    die "缺少 VLESS_URL 环境变量"
  fi

  if [[ "${VLESS_URL}" != vless://* ]]; then
    die "只支持 vless:// 开头的链接"
  fi

  local body without_fragment authority query uuid_part host_port raw_server raw_port
  body="${VLESS_URL#vless://}"
  body="$(printf '%s' "${body}" | sed 's/&amp;/\&/g; s/&#38;/\&/g')"
  without_fragment="${body%%#*}"
  authority="${without_fragment%%\?*}"
  query=""

  if [[ "${without_fragment}" == *\?* ]]; then
    query="${without_fragment#*\?}"
  fi

  [[ "${authority}" == *@* ]] || die "链接格式错误，缺少 uuid@server:port"
  uuid_part="${authority%@*}"
  host_port="${authority#*@}"

  [[ -n "${uuid_part}" ]] || die "缺少 uuid"

  if [[ "${host_port}" == \[*\]:* ]]; then
    raw_server="${host_port%%\]:*}"
    raw_server="${raw_server#[}"
    raw_port="${host_port##*\]:}"
  else
    [[ "${host_port}" == *:* ]] || die "缺少 server_port"
    raw_server="${host_port%:*}"
    raw_port="${host_port##*:}"
  fi

  [[ -n "${raw_server}" ]] || die "缺少 server"
  [[ -n "${raw_port}" ]] || die "缺少 port"

  SB_UUID="$(fallback_url_decode "${uuid_part}")"
  SB_SERVER="$(fallback_url_decode "${raw_server}")"
  SB_PORT="$(fallback_url_decode "${raw_port}")"
  SB_SECURITY=""
  SB_NETWORK="tcp"
  SB_PUBLIC_KEY=""
  SB_SNI=""
  SB_SHORT_ID=""
  SB_FINGERPRINT="chrome"
  SB_FLOW="xtls-rprx-vision"
  SB_SPIDER_X=""

  local pair raw_key raw_value key value
  local -a query_pairs
  IFS='&' read -r -a query_pairs <<< "${query}"
  for pair in "${query_pairs[@]}"; do
    [[ -n "${pair}" ]] || continue
    if [[ "${pair}" == *=* ]]; then
      raw_key="${pair%%=*}"
      raw_value="${pair#*=}"
    else
      raw_key="${pair}"
      raw_value=""
    fi

    key="$(fallback_url_decode "${raw_key}")"
    value="$(fallback_url_decode "${raw_value}")"
    key="${key#amp;}"
    key="${key#\#38;}"

    case "${key}" in
      type) SB_NETWORK="${value:-tcp}" ;;
      security) SB_SECURITY="${value}" ;;
      pbk) SB_PUBLIC_KEY="${value}" ;;
      sni) SB_SNI="${value}" ;;
      sid) SB_SHORT_ID="${value}" ;;
      fp) SB_FINGERPRINT="${value:-chrome}" ;;
      flow) SB_FLOW="${value:-xtls-rprx-vision}" ;;
      spx) SB_SPIDER_X="${value}" ;;
      encryption) ;;
    esac
  done

  [[ "${SB_PORT}" =~ ^[0-9]+$ ]] || die "port 必须是数字，当前值: ${SB_PORT}"
  (( SB_PORT >= 1 && SB_PORT <= 65535 )) || die "port 必须在 1 到 65535 之间，当前值: ${SB_PORT}"
  [[ "${SB_NETWORK}" == "tcp" ]] || die "当前仅支持 type=tcp，当前值: ${SB_NETWORK}"
  [[ -n "${SB_SECURITY}" ]] || die "缺少 security 参数"
  [[ "${SB_SECURITY}" == "reality" ]] || die "只支持 security=reality，当前值: ${SB_SECURITY}"
  [[ -n "${SB_PUBLIC_KEY}" ]] || die "缺少 pbk 参数"
  [[ -n "${SB_SNI}" ]] || die "缺少 sni 参数"

  export SB_UUID SB_SERVER SB_PORT SB_SECURITY SB_NETWORK SB_PUBLIC_KEY SB_SNI
  export SB_SHORT_ID SB_FINGERPRINT SB_FLOW SB_SPIDER_X
}

read_vless_url() {
  if [[ -n "${VLESS_URL:-}" ]]; then
    echo_step "使用环境变量 VLESS_URL 中的 VLESS Reality 节点链接"
    return 0
  fi

  echo_step "等待输入 VLESS Reality 节点链接"
  echo "支持格式：vless://uuid@host:port?type=tcp&security=reality&pbk=xxx&sni=xxx&sid=xxx&fp=chrome&flow=xtls-rprx-vision"
  printf '请输入vless链接：'
  read -r VLESS_URL
  export VLESS_URL

  [[ -n "${VLESS_URL}" ]] || die "VLESS 链接不能为空"
}

parse_vless_link() {
  local script_dir parser_path remote_parser
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  parser_path="${script_dir}/scripts/parse-vless.sh"

  echo_step "解析 VLESS Reality 链接"
  if [[ -f "${parser_path}" ]]; then
    # shellcheck disable=SC1090
    source "${parser_path}"
    return 0
  fi

  if [[ -n "${RAW_BASE_URL:-}" ]]; then
    remote_parser="/tmp/parse-vless.sh"
    echo "未找到本地解析脚本，尝试从 RAW_BASE_URL 下载 scripts/parse-vless.sh..."
    if curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 60 -o "${remote_parser}" "${RAW_BASE_URL%/}/scripts/parse-vless.sh"; then
      # shellcheck disable=SC1090
      source "${remote_parser}"
      return 0
    fi
    echo "下载解析脚本失败，改用 install.sh 内置解析逻辑。"
  else
    echo "未找到本地解析脚本，改用 install.sh 内置解析逻辑。"
  fi

  fallback_parse_vless_url
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\b'/\\b}"
  value="${value//$'\f'/\\f}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

write_sing_box_config() {
  echo_step "生成 ${CONFIG_PATH}"
  mkdir -p /etc/sing-box
  cp "${CONFIG_PATH}" "${CONFIG_PATH}.bak.$(date +%F-%H%M%S)" 2>/dev/null || true

  local json_uuid json_server json_public_key json_sni json_short_id json_fingerprint json_flow
  local reality_spider_line
  json_uuid="$(json_escape "${SB_UUID}")"
  json_server="$(json_escape "${SB_SERVER}")"
  json_public_key="$(json_escape "${SB_PUBLIC_KEY}")"
  json_sni="$(json_escape "${SB_SNI}")"
  json_short_id="$(json_escape "${SB_SHORT_ID}")"
  json_fingerprint="$(json_escape "${SB_FINGERPRINT}")"
  json_flow="$(json_escape "${SB_FLOW}")"
  reality_spider_line=""

  if [[ -n "${SB_SPIDER_X:-}" ]]; then
    reality_spider_line=",
          \"spider_x\": \"$(json_escape "${SB_SPIDER_X}")\""
  fi

  cat > "${CONFIG_PATH}" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": ${LOCAL_PORT}
    }
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "vless-out",
      "server": "${json_server}",
      "server_port": ${SB_PORT},
      "uuid": "${json_uuid}",
      "flow": "${json_flow}",
      "network": "tcp",
      "tls": {
        "enabled": true,
        "server_name": "${json_sni}",
        "utls": {
          "enabled": true,
          "fingerprint": "${json_fingerprint}"
        },
        "reality": {
          "enabled": true,
          "public_key": "${json_public_key}",
          "short_id": "${json_short_id}"${reality_spider_line}
        }
      },
      "packet_encoding": "xudp"
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "vless-out"
  }
}
EOF

  chmod 600 "${CONFIG_PATH}"
}

check_sing_box_config() {
  echo_step "检查 sing-box 配置"
  if ! sing-box check -c "${CONFIG_PATH}"; then
    echo "sing-box check 失败。最近日志如下："
    tail -n 100 "${LOG_PATH}" 2>/dev/null || true
    exit 1
  fi
}

start_sing_box() {
  echo_step "使用 nohup 启动 sing-box"
  pkill -x sing-box 2>/dev/null || true
  nohup sing-box run -c "${CONFIG_PATH}" > "${LOG_PATH}" 2>&1 &
  echo $! > "${PID_PATH}"

  sleep 2

  if ! pgrep -a sing-box; then
    echo "sing-box 启动失败。最近日志如下："
    tail -n 100 "${LOG_PATH}" 2>/dev/null || true
    exit 1
  fi
}

check_local_port() {
  echo_step "检查本地监听端口 ${LOCAL_PORT}"
  if command -v ss >/dev/null 2>&1; then
    ss -lntp 2>/dev/null | grep ":${LOCAL_PORT}" || echo "未在 ss 输出中看到端口 ${LOCAL_PORT}，请查看 ${LOG_PATH}"
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lntp 2>/dev/null | grep ":${LOCAL_PORT}" || echo "未在 netstat 输出中看到端口 ${LOCAL_PORT}，请查看 ${LOG_PATH}"
  else
    echo "未找到 ss 或 netstat，跳过端口检查"
  fi
}

append_proxy_source_to_bashrc() {
  local bashrc="$1"
  local owner="${2:-}"
  local line='[ -f /etc/profile.d/proxy.sh ] && . /etc/profile.d/proxy.sh'

  [[ -n "${bashrc}" ]] || return 0
  touch "${bashrc}" 2>/dev/null || return 0

  if ! grep -Fxq "${line}" "${bashrc}" 2>/dev/null; then
    printf '\n%s\n' "${line}" >> "${bashrc}"
  fi

  if [[ -n "${owner}" ]]; then
    chown "${owner}" "${bashrc}" 2>/dev/null || true
  fi
}

write_proxy_env() {
  echo_step "写入终端代理环境变量"
  cat > /etc/profile.d/proxy.sh <<EOF
export http_proxy="http://127.0.0.1:${LOCAL_PORT}"
export https_proxy="http://127.0.0.1:${LOCAL_PORT}"
export all_proxy="socks5h://127.0.0.1:${LOCAL_PORT}"

export HTTP_PROXY="\$http_proxy"
export HTTPS_PROXY="\$https_proxy"
export ALL_PROXY="\$all_proxy"

export no_proxy="localhost,127.0.0.1,::1"
export NO_PROXY="\$no_proxy"
EOF

  chmod +x /etc/profile.d/proxy.sh

  append_proxy_source_to_bashrc "${HOME:-/root}/.bashrc"

  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]] && command -v getent >/dev/null 2>&1; then
    local sudo_home
    sudo_home="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
    if [[ -n "${sudo_home}" && -d "${sudo_home}" ]]; then
      append_proxy_source_to_bashrc "${sudo_home}/.bashrc" "${SUDO_USER}"
    fi
  fi

  # shellcheck disable=SC1091
  source /etc/profile.d/proxy.sh

  echo "当前代理环境变量："
  env | grep -i proxy || true
}

test_proxy_ip() {
  echo_step "测试代理出口 IP"
  curl -x "socks5h://127.0.0.1:${LOCAL_PORT}" --connect-timeout 10 --max-time 30 https://api.ipify.org || true
  echo
}

print_success() {
  echo
  echo "完成。"
  echo "本地代理地址：127.0.0.1:${LOCAL_PORT}"
  echo "配置文件：${CONFIG_PATH}"
  echo "日志文件：${LOG_PATH}"
  echo "停止命令：pkill -x sing-box"
  echo "查看日志：tail -n 100 ${LOG_PATH}"
}

main() {
  require_root
  validate_local_port
  read_vless_url
  parse_vless_link
  install_sing_box
  write_sing_box_config
  check_sing_box_config
  start_sing_box
  check_local_port
  write_proxy_env
  test_proxy_ip
  print_success
}

main "$@"
