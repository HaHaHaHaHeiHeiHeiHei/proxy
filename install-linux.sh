#!/usr/bin/env bash
set -e

echo_step() {
  echo
  echo "==> $*"
}

die() {
  echo "错误: $*" >&2
  exit 1
}

is_debian_like() {
  if [[ ! -r /etc/os-release ]]; then
    return 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  case " ${ID:-} ${ID_LIKE:-} " in
    *" debian "*|*" ubuntu "*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

run_install_sh() {
  local script_dir install_path remote_install
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  install_path="${script_dir}/install.sh"

  if [[ -f "${install_path}" ]]; then
    exec bash "${install_path}"
  fi

  if [[ -n "${RAW_BASE_URL:-}" ]]; then
    remote_install="/tmp/install-singbox.sh"
    echo_step "未找到本地 install.sh，尝试从 RAW_BASE_URL 下载"
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 60 -o "${remote_install}" "${RAW_BASE_URL%/}/install.sh" \
      || die "下载 install.sh 失败，请检查 RAW_BASE_URL"
    exec bash "${remote_install}"
  fi

  die "未找到 install.sh。请在完整项目目录中运行，或设置 RAW_BASE_URL=https://raw.githubusercontent.com/HaHaHaHaHeiHeiHeiHei/proxy/main 后重试"
}

if is_debian_like; then
  echo_step "检测到 Debian / Ubuntu，调用 install.sh"
  run_install_sh
fi

echo "当前系统暂不支持自动安装 deb 包。"
echo "请手动安装 sing-box 后，再运行本项目的配置逻辑。"
echo
echo "如果你已经手动安装 sing-box，可以在完整项目目录中运行："
echo "  sudo env SKIP_SING_BOX_DEB_INSTALL=1 bash install.sh"
echo
echo "如果你只下载了 install-linux.sh，请先下载完整项目，或设置 RAW_BASE_URL 后重试。"
exit 1
