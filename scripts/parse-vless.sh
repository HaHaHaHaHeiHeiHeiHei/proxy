#!/usr/bin/env bash
set -e

vless_error() {
  echo "错误: $*" >&2
  return 1
}

url_decode() {
  local encoded="${1//+/ }"
  printf '%b' "${encoded//%/\\x}"
}

parse_vless_url() {
  if [[ -n "${1:-}" && -z "${VLESS_URL:-}" ]]; then
    VLESS_URL="$1"
  fi

  if [[ -z "${VLESS_URL:-}" ]]; then
    vless_error "缺少 VLESS_URL 环境变量"
    return 1
  fi

  if [[ "${VLESS_URL}" != vless://* ]]; then
    vless_error "只支持 vless:// 开头的链接"
    return 1
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

  if [[ "${authority}" != *@* ]]; then
    vless_error "链接格式错误，缺少 uuid@server:port"
    return 1
  fi

  uuid_part="${authority%@*}"
  host_port="${authority#*@}"

  if [[ -z "${uuid_part}" ]]; then
    vless_error "缺少 uuid"
    return 1
  fi

  if [[ "${host_port}" == \[*\]:* ]]; then
    raw_server="${host_port%%\]:*}"
    raw_server="${raw_server#[}"
    raw_port="${host_port##*\]:}"
  else
    if [[ "${host_port}" != *:* ]]; then
      vless_error "缺少 server_port"
      return 1
    fi
    raw_server="${host_port%:*}"
    raw_port="${host_port##*:}"
  fi

  if [[ -z "${raw_server}" ]]; then
    vless_error "缺少 server"
    return 1
  fi

  if [[ -z "${raw_port}" ]]; then
    vless_error "缺少 port"
    return 1
  fi

  SB_UUID="$(url_decode "${uuid_part}")"
  SB_SERVER="$(url_decode "${raw_server}")"
  SB_PORT="$(url_decode "${raw_port}")"
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

    key="$(url_decode "${raw_key}")"
    value="$(url_decode "${raw_value}")"
    key="${key#amp;}"
    key="${key#\#38;}"

    case "${key}" in
      type)
        SB_NETWORK="${value:-tcp}"
        ;;
      security)
        SB_SECURITY="${value}"
        ;;
      pbk)
        SB_PUBLIC_KEY="${value}"
        ;;
      sni)
        SB_SNI="${value}"
        ;;
      sid)
        SB_SHORT_ID="${value}"
        ;;
      fp)
        SB_FINGERPRINT="${value:-chrome}"
        ;;
      flow)
        SB_FLOW="${value:-xtls-rprx-vision}"
        ;;
      spx)
        SB_SPIDER_X="${value}"
        ;;
      encryption)
        ;;
    esac
  done

  if [[ ! "${SB_PORT}" =~ ^[0-9]+$ ]]; then
    vless_error "port 必须是数字，当前值: ${SB_PORT}"
    return 1
  fi

  if (( SB_PORT < 1 || SB_PORT > 65535 )); then
    vless_error "port 必须在 1 到 65535 之间，当前值: ${SB_PORT}"
    return 1
  fi

  if [[ "${SB_NETWORK}" != "tcp" ]]; then
    vless_error "当前仅支持 type=tcp，当前值: ${SB_NETWORK}"
    return 1
  fi

  if [[ -z "${SB_SECURITY}" ]]; then
    vless_error "缺少 security 参数"
    return 1
  fi

  if [[ "${SB_SECURITY}" != "reality" ]]; then
    vless_error "只支持 security=reality，当前值: ${SB_SECURITY}"
    return 1
  fi

  if [[ -z "${SB_PUBLIC_KEY}" ]]; then
    vless_error "缺少 pbk 参数"
    return 1
  fi

  if [[ -z "${SB_SNI}" ]]; then
    vless_error "缺少 sni 参数"
    return 1
  fi

  export SB_UUID
  export SB_SERVER
  export SB_PORT
  export SB_SECURITY
  export SB_NETWORK
  export SB_PUBLIC_KEY
  export SB_SNI
  export SB_SHORT_ID
  export SB_FINGERPRINT
  export SB_FLOW
  export SB_SPIDER_X
}

parse_vless_url "$@"
