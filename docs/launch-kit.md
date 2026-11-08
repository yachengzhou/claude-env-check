# 发布与引流清单 · Launch Kit

目标：让真正有需求的人看到工具。所有渠道均为免费的自然流量，**不购买 star、不刷量、不群发骚扰**（违反 GitHub / 平台规则，且会毁掉项目信誉）。

## 一句话定位

> 浏览器里 30 秒自查：你的 IP、时区、语言、字体、WebRTC、IPv6、DNS、TUN 是否互相矛盾。发现问题后，一条命令修好（Windows / Ubuntu）。

## 已就绪的素材

- 在线站点：https://yachengzhou.github.io/claude-env-check/
- 分享图：页面「分享结果」按钮自动生成 1200×630 PNG，含分数与主要冲突项
- 仓库：https://github.com/yachengzhou/claude-env-check
- 开源协议：MIT，可直接引用、转发、二次开发

## 发布节奏（按重要性排序）

1. **V2EX · 分享创造**：中文技术社区，转化率最高，标题克制、正文讲清原理与可回滚。
2. **Linux.do**：代理/网络环境用户集中，重点是 WebRTC / DNS / IPv6 泄漏检测。
3. **X（Twitter）中英双帖**：配分享图，带 `#Claude #ChatGPT #隐私 #WebRTC`。
4. **Reddit**：`r/ClaudeAI`、`r/ChatGPT`、`r/privacy`。必须先读版规，只发一次，正文以「我发现的问题 + 工具」为主，不要纯广告。
5. **Hacker News · Show HN**：英文、技术细节、无营销词，标题 `Show HN: Local browser check for proxy/IP/timezone consistency`。
6. **即刻 / 小红书**：用分享图做首图，讲「我被自己的环境出卖了」的故事。
7. **相关 Telegram / Discord 群**：仅在群规允许自荐时发一次。

## 可直接复制的文案

### V2EX（标题：分享一个本地运行的 Claude/ChatGPT 环境自检工具）

> 最近在排查账号被风控的问题，发现真正麻烦的不是 IP 本身，而是环境之间互相矛盾：IP 在美国，系统时区是 UTC+8，浏览器首选语言 zh-CN，字体里还有中文环境才有的黑体楷体。
>
> 写了个纯前端的小工具，浏览器本地跑完 15 项检测，给出 0-100 的冲突分：
> - 出口 IP 归属地 / 是否机房 IP
> - 系统时区、语言、Intl、时区偏移
> - 字体指纹、WebGL / Canvas / Audio
> - WebRTC 真实 IP、IPv6 绕过、DNS 出口
> - TUN 隧道、代理进程、路由、权限
>
> 发现问题后可以直接下载修复脚本：Windows 一个 bat，Ubuntu 一个 sh，修复和还原都在里面，改坏了随时 restore。全部开源，不上传任何数据。
>
> 在线：https://yachengzhou.github.io/claude-env-check/
> 源码：https://github.com/yachengzhou/claude-env-check
>
> 欢迎反馈误判项，尤其是 macOS 和 Ubuntu 上的检测差异。

### X / Twitter（中文）

> IP 在美国，系统时区却是 UTC+8，浏览器首选语言 zh-CN，字体还带着中文环境专有字体——这四件事同时出现，比 IP 本身更显眼。
>
> 做了个纯本地跑的环境自检工具：15 项信号、0-100 冲突分、Windows/Ubuntu 一键修复脚本。
> 免费开源，不上传任何数据。
> https://yachengzhou.github.io/claude-env-check/

### X / Twitter (English)

> Your IP says US, your system timezone says UTC+8, your browser prefers zh-CN, and your font list includes Chinese-only fonts. That combination is what gets flagged.
>
> Built a local-only checker: 15 signals, 0-100 conflict score, one-file fix scripts for Windows and Ubuntu. Free, open source, nothing uploaded.
> https://yachengzhou.github.io/claude-env-check/

### Show HN

> **Show HN: Local browser check for proxy/IP/timezone consistency**
>
> I kept seeing accounts flagged for environment mismatches rather than the proxy itself: exit IP in one country, OS timezone in another, browser language and font list pointing somewhere else. WebRTC, IPv6 and DNS can also bypass the tunnel and expose the real address.
>
> The site runs entirely in the browser: 15 weighted signals, a 0-100 conflict score, and per-item advice. No account, no upload. It also ships two single-file fix scripts (Windows .bat, Ubuntu .sh) that apply browser policy, block non-proxied UDP, disable IPv6 binding, set DoH and check TUN state — every change has a matching restore command.
>
> Source: https://github.com/yachengzhou/claude-env-check
> Demo: https://yachengzhou.github.io/claude-env-check/
>
> Feedback on false positives (especially macOS / Ubuntu font detection) is very welcome.

## GitHub 侧优化（已做 / 待做）

- [x] 仓库简介、主页链接、topics（claude / chatgpt / privacy / webrtc / dns-leak / tun2socks …）
- [x] 中英双语 README、对比表、徽章、MIT License
- [x] 页面「分享结果」生成 PNG 卡片，方便二次传播
- [ ] 手动上传社交预览图（Settings → Social preview，用 `og-cover.jpg`）
- [x] 发布 v1.0.0 Release，附在线地址与下载链接
- [x] README 顶部放入真实检测截图（`docs/preview.png`）
- [x] 页面内置「一键转发」X / Telegram / 微博入口，降低二次传播成本

## 合规红线

- 不购买、不交换、不互刷 star；不使用自动化账号点赞。
- 不在无关仓库提 PR / Issue 打广告；awesome-list 只在项目确实符合收录标准时提交。
- 同一社区只发一次，遵守版规与自荐比例要求。
- 明确作者身份，不伪装成第三方推荐。

## 预期管理

自然流量下，24 小时 200 star 属于爆款级别，取决于帖子是否被推荐、是否有大号转发，无法承诺。可控的是：产品质量、素材完备度、发布渠道与时机。以上清单已把可控部分做到位。
