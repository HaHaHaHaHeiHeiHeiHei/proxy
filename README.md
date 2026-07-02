# sing-box VLESS Reality Local Proxy Installer

这是一个用于 Ubuntu / Debian 的 sing-box + VLESS Reality 本地代理安装器。运行后输入你自己的 VLESS Reality 节点链接，即可在本机启动 `127.0.0.1:10808` 本地代理。

本项目不提供任何节点，只负责把用户自己的 VLESS Reality 链接转换为 sing-box 配置，并写入用户服务器本地的 `/etc/sing-box/config.json`。

## 安全提醒

- 不要把自己的真实 VLESS 链接提交到 GitHub。
- 不要在公开 issue、讨论区或日志截图里粘贴真实节点。
- 仓库中不要保存真实 UUID、服务器地址、公钥、short id、SNI 或订阅链接。
- README 中的 VLESS 链接全部是示例参数，不能作为真实节点使用。

## Ubuntu / Debian 一键运行

把 `<your-username>/<your-repo>` 替换成你发布后的 GitHub 用户名和仓库名：

```bash
curl -fsSL https://raw.githubusercontent.com/<your-username>/<your-repo>/main/install.sh -o /tmp/install-singbox.sh && sudo bash /tmp/install-singbox.sh
```

脚本会提示输入 VLESS Reality 节点链接：

```text
请输入 VLESS Reality 节点链接：
支持格式：vless://uuid@host:port?type=tcp&security=reality&pbk=xxx&sni=xxx&sid=xxx&fp=chrome&flow=xtls-rprx-vision
```

## 其他 Linux

Ubuntu / Debian 是主支持平台。其他 Linux 可以先运行通用入口查看提示：

```bash
curl -fsSL https://raw.githubusercontent.com/<your-username>/<your-repo>/main/install-linux.sh -o /tmp/install-singbox-linux.sh && sudo bash /tmp/install-singbox-linux.sh
```

如果系统不是 Debian / Ubuntu，脚本会提示当前系统暂不支持自动安装 deb 包。你可以手动安装 sing-box 后，在完整项目目录中运行：

```bash
sudo env SKIP_SING_BOX_DEB_INSTALL=1 bash install.sh
```

## 非交互式运行

可以通过 `VLESS_URL` 环境变量传入链接，脚本就不会再提示输入：

```bash
sudo env VLESS_URL='vless://00000000-0000-0000-0000-000000000000@example.com:443?type=tcp&encryption=none&security=reality&pbk=example_public_key&fp=chrome&sni=example.com&sid=example_short_id&spx=%2F&flow=xtls-rprx-vision' bash install.sh
```

单文件一键运行时也可以这样传入：

```bash
curl -fsSL https://raw.githubusercontent.com/<your-username>/<your-repo>/main/install.sh -o /tmp/install-singbox.sh && sudo env VLESS_URL='vless://00000000-0000-0000-0000-000000000000@example.com:443?type=tcp&encryption=none&security=reality&pbk=example_public_key&fp=chrome&sni=example.com&sid=example_short_id&spx=%2F&flow=xtls-rprx-vision' bash /tmp/install-singbox.sh
```

## 自定义端口

默认本地代理端口是 `10808`。可以用 `LOCAL_PORT` 覆盖：

```bash
sudo env LOCAL_PORT=10809 bash install.sh
```

安装完成后，本地代理地址会变为 `127.0.0.1:10809`。

## 自定义 sing-box 版本

默认安装 `1.13.14`。可以用 `VERSION` 覆盖：

```bash
sudo env VERSION=1.13.14 bash install.sh
```

脚本会下载对应版本的 sing-box deb 包，例如 `sing-box_1.13.14_linux_amd64.deb`。

## 支持的链接参数

脚本只支持 `vless://` 开头且 `security=reality` 的链接。会解析这些字段：

- `uuid`
- `server`
- `port`
- `type`，缺省为 `tcp`
- `security`，必须为 `reality`
- `pbk`，写入 `reality.public_key`
- `sni`，写入 `tls.server_name`
- `sid`，写入 `reality.short_id`，缺省为空字符串
- `fp`，缺省为 `chrome`
- `flow`，缺省为 `xtls-rprx-vision`
- `spx`，可选，URL decode 后写入 `reality.spider_x`

## 常用命令

查看进程：

```bash
pgrep -a sing-box
```

查看端口：

```bash
ss -lntp | grep 10808
```

查看日志：

```bash
tail -n 100 /var/log/sing-box.log
```

停止 sing-box：

```bash
sudo pkill -x sing-box
```

取消当前 shell 的代理环境变量：

```bash
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
```

如果还想取消后续 shell 自动加载代理，可以删除 profile 文件，并移除 `.bashrc` 中对应的 source 行：

```bash
sudo rm -f /etc/profile.d/proxy.sh
sed -i '\#\[ -f /etc/profile.d/proxy.sh \] && \. /etc/profile.d/proxy.sh#d' ~/.bashrc
```

## 生成的文件

安装脚本会在目标机器上生成或使用这些路径：

- `/etc/sing-box/config.json`
- `/etc/profile.d/proxy.sh`
- `/var/log/sing-box.log`
- `/tmp/sing-box.pid`

生成新配置前会尝试备份旧配置：

```bash
cp /etc/sing-box/config.json /etc/sing-box/config.json.bak.$(date +%F-%H%M%S) 2>/dev/null || true
```
