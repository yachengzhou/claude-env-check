# Claude 环境自检 · Claude Env Check

在浏览器里一次性检查你的 **IP、时区、浏览器语言、字体、WebRTC、IPv6、DNS、TUN 隧道** 是否互相矛盾，并给出可直接运行的修复脚本。

An in-browser self-check for the environment signals that overseas services (Claude, ChatGPT, etc.) look at — plus one-file fix scripts for Windows and Ubuntu.

**在线使用 / Live demo:** https://yachengzhou.github.io/claude-env-check/

[![Stars](https://img.shields.io/github/stars/yachengzhou/claude-env-check?style=social)](https://github.com/yachengzhou/claude-env-check/stargazers)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Deploy](https://img.shields.io/github/actions/workflow/status/yachengzhou/claude-env-check/pages.yml?label=pages)](https://github.com/yachengzhou/claude-env-check/actions)

![preview](og-cover.jpg)

> 如果这个工具帮你发现了问题，点一个 Star 就是最好的支持。If this tool helped you, a star is the best way to say thanks.

[中文](#中文) · [English](#english)

---

## 中文

### 这是什么

Claude、ChatGPT 这类服务在风控时，不只看你的 IP 在哪个国家，还会看你的环境信息是不是**自洽**：

- IP 显示在美国，系统时区却是 UTC+8
- 浏览器首选语言是 `zh-CN`
- 系统里装着只有中文环境才会出现的字体
- WebRTC / IPv6 / DNS 绕过代理，把真实地址漏了出去
- 代理客户端开了 TUN，但路由或 DNS 没走对

任何一项对不上，都可能让账号被标记。这个工具做的事，就是把这些信号一次性摊开，告诉你哪几项矛盾、怎么改。

### 和同类工具比

| 能力 | 本项目 | fuck-claude.app |
| --- | :---: | :---: |
| 浏览器指纹检测项 | 15 项 | 11 项 |
| 出口 IP 归属地与机房标记 | 支持 | 无 |
| WebRTC / IPv6 / DNS 真实泄漏检测 | 支持 | 无 |
| TUN 隧道与代理进程检查 | 支持 | 无 |
| 一键修复脚本（Windows + Ubuntu） | 支持 | 无 |
| 时区查看 / 修改 / 还原 | 支持 | 仅提示修改 |
| 分享结果图 | 支持 | 无 |
| 中英双语 | 支持 | 英文 |

差异不是为了贬低谁，而是说明：**它能告诉你「哪里不对」，我们还能帮你「直接改好」。**


### 隐私说明

- 所有检测都在**你的浏览器本地**完成，不上传、不保存任何数据。
- 只有你主动启动了本地脚本服务，页面才会访问 `127.0.0.1:8788`，该服务**只监听本机回环地址**，局域网内其他设备无法访问。

### 三步开始

1. 打开在线页面，点「开始检测」。
2. 看报告：风险分 0–100，**0–30 低风险，31–60 中等，61–100 高风险**。
3. 看到红色的「加固 / 修复」按钮，点它下载脚本，按页面提示的命令执行。

### 检测哪些项

| 检测项 | 权重 | 通俗解释 |
| --- | ---: | --- |
| IP 出口 | 14 | 你的 IP 在哪个国家、是不是机房 IP |
| 系统时区 | 18 | 系统时区是否和 IP 所在地对得上 |
| 浏览器语言 | 14 | 首选语言是否和 IP 所在地区常用语言一致 |
| 字体指纹 | 11 | 是否装了只有中文环境才有的字体 |
| Intl 区域 | 6 | 浏览器上报的区域设置是否和 IP 一致 |
| 时区偏移 | 4 | 偏移量是否与系统时区自相印证 |
| Emoji 风格 | 3 | 用于佐证操作系统类型，不反映地区 |
| WebGL 渲染器 | 3 | 显卡/系统信息，用于佐证设备一致性 |
| Canvas 指纹 | 2 | 设备指纹稳定性参考 |
| 音频指纹 | 2 | 设备指纹稳定性参考 |
| 硬件与屏幕 | 2 | CPU 核数、内存、分辨率是否自然 |
| WebRTC 本地 IP | 6 | 是否绕过代理暴露真实公网 IP |
| IPv6 绕过 | 5 | IPv6 是否可直连并绕过代理 |
| DNS 出口 | 4 | DNS 查询是否和流量走同一出口 |
| 隧道检查 | 6 | TUN 模式、代理进程、路由、权限是否正常 |

其中「隧道检查」需要本地服务在运行，其余项直接在浏览器里算。

### 修复脚本

只提供**两个文件**，每个系统一个，所有功能都在里面：

| 系统 | 文件 | 运行方式 |
| --- | --- | --- |
| Windows 10 / 11 | `env-fix.bat` | 双击，按菜单选择；或命令行运行 |
| Ubuntu / Debian 等 Linux | `env-fix.sh` | `chmod +x env-fix.sh` 后执行 |

- Windows 版会自动申请管理员权限。若弹出「Windows 已保护你的电脑」，点「更多信息 → 仍要运行」。
- Linux 版在终端里用 `sudo`，桌面环境会自动调用 `pkexec` 弹窗提权。
- 两个脚本都支持**修复**和**一键还原**，改完不满意可以原样退回去。

下载地址（也可以直接从页面点按钮下载）：

- https://yachengzhou.github.io/claude-env-check/env-fix.bat
- https://yachengzhou.github.io/claude-env-check/env-fix.sh

### 命令一览

| 作用 | Windows | Ubuntu / Linux |
| --- | --- | --- |
| 打开交互菜单 | `env-fix.bat` | `./env-fix.sh` |
| 修复全部 | `env-fix.bat fix all` | `sudo ./env-fix.sh fix all` |
| 修复 WebRTC | `env-fix.bat fix webrtc` | `sudo ./env-fix.sh fix webrtc` |
| 修复 IPv6 | `env-fix.bat fix ipv6` | `sudo ./env-fix.sh fix ipv6` |
| 修复 DNS | `env-fix.bat fix dns` | `sudo ./env-fix.sh fix dns` |
| 还原全部 | `env-fix.bat restore all` | `sudo ./env-fix.sh restore all` |
| 检查 TUN 隧道 | `env-fix.bat check` | `./env-fix.sh check` |
| 自动开启 TUN | `env-fix.bat tun-fix` | `sudo ./env-fix.sh tun-fix` |
| TUN 异常兜底 | `env-fix.bat tun-fallback` | `./env-fix.sh tun-fallback` |
| 启动本地检查服务 | `env-fix.bat serve` | `./env-fix.sh serve` |
| 查看当前时区 | `env-fix.bat tz` | `./env-fix.sh tz` |
| 修改时区 | `env-fix.bat tz set Asia/Shanghai` | `sudo ./env-fix.sh tz set Asia/Shanghai` |
| 还原时区 | `env-fix.bat tz restore` | `sudo ./env-fix.sh tz restore` |

### 本地检查服务（可选）

页面上的「隧道检查」需要读取本机的 TUN 状态，浏览器做不到，所以脚本内置了一个极小的本地服务：

```bash
# Windows
env-fix.bat serve

# Ubuntu / Linux
./env-fix.sh serve
```

启动后：

- 线上页面也能读到 TUN 检查结果（服务已处理浏览器的私有网络访问预检请求）。
- 也可以直接打开 http://127.0.0.1:8788/ 使用离线版页面。

> Linux 下的本地服务依赖 `python3`（Ubuntu/Debian 默认自带），不需要安装其他任何东西。

### 常见问题

**Q：不挂代理能用吗？**
检测本身能用，但结果的参考价值不大——这个工具的用途就是检查「代理出口 + 本机环境」是否自洽。

**Q：修复会影响我正常上网吗？**
WebRTC 修复只写浏览器策略并阻断浏览器出站 UDP，不影响系统网络；IPv6、DNS、时区都有对应的 `restore` 命令可随时还原。

**Q：为什么 DNS 出口 IP 和代理节点 IP 不一样？**
正常。用 8.8.8.8、1.1.1.1 这类公共 DNS 时，递归出口本来就是 DNS 服务商自己的地址，只要地区一致就不算泄漏。

**Q：分数低就一定不会被封吗？**
不能保证。风控是多维的，还包括支付方式、手机号、账号行为等，本工具只覆盖「环境一致性」这一层。

**Q：这些脚本安全吗？**
全部开源，单文件、无外部依赖、不上传任何数据，可以直接打开阅读每一行。运行时产生的状态与备份保存在本机：Windows 为 `%LOCALAPPDATA%\env-check`，Linux 为 `/var/lib/env-check`。

### 免责声明

本项目仅供学习、隐私自查与环境调试使用。在非官方支持的地区使用第三方服务可能违反其服务条款，是否使用及由此产生的后果由使用者自行承担。

---

## English

### What is this

Services like Claude and ChatGPT don't only look at which country your IP is in — they also check whether your environment is **self-consistent**:

- IP says United States, but the system time zone is UTC+8
- Browser's preferred language is `zh-CN`
- The system has fonts that only Chinese-language installs carry
- WebRTC / IPv6 / DNS bypass the proxy and leak your real address
- TUN is enabled, but routing or DNS isn't actually going through it

Any single mismatch can get an account flagged. This tool lays all of those signals out at once and tells you which ones conflict — and how to fix them.

### Compared with similar tools

| Capability | This project | fuck-claude.app |
| --- | :---: | :---: |
| Browser fingerprint signals | 15 | 11 |
| Exit IP geolocation and hosting flag | Yes | No |
| Real WebRTC / IPv6 / DNS leak detection | Yes | No |
| TUN tunnel and proxy process check | Yes | No |
| One-click fix scripts (Windows + Ubuntu) | Yes | No |
| View / set / restore system time zone | Yes | Advice only |
| Shareable result card | Yes | No |
| Chinese + English | Yes | English |

The point isn't to disparage anyone: **others tell you what's wrong — we also fix it for you.**

### Privacy

- Every check runs **locally in your browser**. Nothing is uploaded or stored.
- The page only talks to `127.0.0.1:8788` if you start the local script service yourself, and that service listens on the loopback interface only.

### Three steps

1. Open the live page and click "Start check".
2. Read the report: risk score 0–100 — **0–30 low, 31–60 medium, 61–100 high**.
3. For any red "Fix" button, click it to download the script and run the command shown.

### What gets checked

| Signal | Weight | In plain words |
| --- | ---: | --- |
| IP exit | 14 | Which country your IP is in, and whether it's a datacenter IP |
| System time zone | 18 | Whether it matches the IP's region |
| Browser language | 14 | Whether the preferred language fits that region |
| Font fingerprint | 11 | Whether Chinese-only fonts are installed |
| Intl locale | 6 | Whether the browser's locale matches the IP |
| Time zone offset | 4 | Cross-checks the system time zone |
| Emoji rendering | 3 | Indicates OS type only, not region |
| WebGL renderer | 3 | GPU/OS hint for device consistency |
| Canvas fingerprint | 2 | Device fingerprint stability |
| Audio fingerprint | 2 | Device fingerprint stability |
| Hardware & screen | 2 | CPU cores, memory, resolution |
| WebRTC local IP | 6 | Whether the real public IP leaks past the proxy |
| IPv6 bypass | 5 | Whether IPv6 can bypass the proxy |
| DNS exit | 4 | Whether DNS queries leave through the same exit |
| Tunnel check | 6 | TUN mode, proxy process, routes, permissions |

"Tunnel check" needs the local service running; everything else is computed in the browser.

### Fix scripts

Just **two files**, one per OS, each with every feature built in:

| OS | File | How to run |
| --- | --- | --- |
| Windows 10 / 11 | `env-fix.bat` | Double-click and pick from the menu, or run from a terminal |
| Ubuntu / Debian / other Linux | `env-fix.sh` | `chmod +x env-fix.sh`, then run it |

- The Windows script requests administrator rights automatically. If SmartScreen appears, choose "More info → Run anyway".
- On Linux, use `sudo` in a terminal; on desktop it elevates through `pkexec`.
- Both scripts support **fix** and **restore**, so every change can be rolled back.

Direct downloads (the page's buttons use the same files):

- https://yachengzhou.github.io/claude-env-check/env-fix.bat
- https://yachengzhou.github.io/claude-env-check/env-fix.sh

### Commands

| Action | Windows | Ubuntu / Linux |
| --- | --- | --- |
| Open interactive menu | `env-fix.bat` | `./env-fix.sh` |
| Fix everything | `env-fix.bat fix all` | `sudo ./env-fix.sh fix all` |
| Fix WebRTC | `env-fix.bat fix webrtc` | `sudo ./env-fix.sh fix webrtc` |
| Fix IPv6 | `env-fix.bat fix ipv6` | `sudo ./env-fix.sh fix ipv6` |
| Fix DNS | `env-fix.bat fix dns` | `sudo ./env-fix.sh fix dns` |
| Restore everything | `env-fix.bat restore all` | `sudo ./env-fix.sh restore all` |
| Check TUN | `env-fix.bat check` | `./env-fix.sh check` |
| Auto-enable TUN | `env-fix.bat tun-fix` | `sudo ./env-fix.sh tun-fix` |
| TUN fallback | `env-fix.bat tun-fallback` | `./env-fix.sh tun-fallback` |
| Start local service | `env-fix.bat serve` | `./env-fix.sh serve` |
| Show time zone | `env-fix.bat tz` | `./env-fix.sh tz` |
| Set time zone | `env-fix.bat tz set Asia/Shanghai` | `sudo ./env-fix.sh tz set Asia/Shanghai` |
| Restore time zone | `env-fix.bat tz restore` | `sudo ./env-fix.sh tz restore` |

### Local check service (optional)

A browser can't read TUN state by itself, so the script ships a tiny local service:

```bash
# Windows
env-fix.bat serve

# Ubuntu / Linux
./env-fix.sh serve
```

Once running:

- The online page can read TUN results too (the service answers the browser's Private Network Access preflight).
- You can also open http://127.0.0.1:8788/ for a purely local copy of the page.

> On Linux the service needs `python3` (preinstalled on Ubuntu/Debian). Nothing else to install.

### FAQ

**Can I use this without a proxy?**
Yes, but the results won't tell you much — the whole point is comparing your proxy exit against your local environment.

**Will fixing break my network?**
The WebRTC fix only writes browser policy and blocks the browser's outbound UDP. IPv6, DNS and time zone changes each have a matching `restore` command.

**Why is my DNS exit IP different from my proxy IP?**
That's normal with public resolvers like 8.8.8.8 or 1.1.1.1 — the recursive exit belongs to the DNS provider. Same region means no leak.

**Does a low score mean I'm safe?**
No guarantee. Risk systems also weigh payment method, phone number and account behaviour; this tool only covers environment consistency.

**Are the scripts safe?**
They're fully open source, single-file, dependency-free and upload nothing. Runtime state and backups stay on your machine: `%LOCALAPPDATA%\env-check` on Windows, `/var/lib/env-check` on Linux.

### Disclaimer

This project is for learning, privacy self-checking and environment debugging. Using third-party services outside their supported regions may violate their terms of service; you are responsible for how you use it.
