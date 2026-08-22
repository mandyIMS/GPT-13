# GPT-13

[English](README.md)

这是一个面向较旧 iPhone 的非官方、基于 Gecko 的 ChatGPT Web 客户端。它直接打开
`chatgpt.com`，而不是嵌入 Apple WebKit，因此在系统自带 WebKit 已无法兼容 ChatGPT
网站的设备上仍可使用。

本项目**不隶属于、未经 OpenAI 认可，也未获得其赞助**。ChatGPT 与 OpenAI 是其各自
权利人的商标。

## 致谢

GPT-13 是 [Reynard Browser](https://github.com/minh-ton/reynard-browser) 的聚焦派生项目。
Reynard Browser 提供了本项目所依赖的原始 iOS 应用结构与 Gecko 集成基础；GPT-13 在此
基础上收窄为单一 ChatGPT 客户端，并加入面向 TrollStore 的工作流。完整的上游与第三方
致谢请见原项目及 [NOTICE.md](NOTICE.md)。

## 状态

GPT-13 是面向 iOS 13 及以上版本的实验性软件。当前版本主要在已安装 TrollStore 的
iPhone 13 Pro（iOS 15.3.1）上测试。

它是一个单站点客户端，而非完整网页浏览器：

- 在应用内打开 ChatGPT；
- 保留 ChatGPT 的网页登录状态与网站数据；
- 将普通外部链接交给系统默认浏览器；
- 支持 ChatGPT 网页请求的文件、照片、相机、麦克风与语音权限；
- 提供下载列表与限定范围的网站数据清理；
- 提供 Gecko 的 TrollStore JIT 支持。

## 安装

从项目的 [Releases](https://github.com/JKleissJL/GPT-13/releases) 页面下载
`ReynardGPT-TrollStore.tipa`，传输到 iPhone 后使用 TrollStore 安装。

首次启动时，Gecko 创建配置文件可能需要数秒。该软件包仅适用于支持 TrollStore 的设备；
请勿通过签名服务或分发证书安装。

## 重要说明

- 需要正常的 ChatGPT 帐号。本项目不包含 API Key，也不会提供任何 OpenAI 付费计划额度。
- 登录、下载、上传可用性及语音功能均由 ChatGPT 网页提供，可能会独立于本项目发生变化。
- 内嵌视图会放行 ChatGPT 及其登录/挑战域名；用户主动打开的其他网站会交给系统浏览器。
- 这不是官方 OpenAI 应用。请勿将本项目的问题作为官方应用问题报告给 OpenAI。

## 构建

项目在 macOS 上开发，需要 Xcode、Rust、`ldid`、`xcodegen` 及兼容 Apple Silicon 的
Gecko 工具链。克隆时包含子模块：

```bash
git clone --recursive https://github.com/JKleissJL/GPT-13.git
cd GPT-13
```

获取并打补丁，然后构建 Gecko：

```bash
tools/development/update-gecko.sh
tools/development/apply-patches.sh
tools/development/build-gecko.sh
```

创建并校验 TrollStore 软件包：

```bash
tools/release/build-reynardgpt.sh
tools/release/create-reynardgpt-tipa.sh
tools/release/verify-reynardgpt-tipa.sh
```

生成的软件包位于 `dist/ReynardGPT-TrollStore.tipa`。构建产物不会提交至 Git；可安装
软件包会作为 GitHub Release 附件发布。

## 开发与测试

应用主体代码位于 `browser/ReynardGPT/`；Gecko UIKit 兼容性修改位于
`patches/widget/uikit/`。真机测试清单见
[`docs/ReynardGPT-Device-Test.md`](docs/ReynardGPT-Device-Test.md)。不要在 bug 报告中
分享 Gecko 配置文件、Cookie、登录令牌或应用容器。

## 上游与许可证

GPT-13 派生自 Reynard Browser，并通过固定版本的 Git 子模块嵌入 Mozilla Firefox Gecko。
上游与第三方致谢记录在 [NOTICE.md](NOTICE.md)。

项目源码采用 GPL-3.0；`patches/` 下修改 Firefox Gecko 的文件采用 MPL-2.0。详见
[LICENSE](LICENSE) 与 [LICENSE.firefox](LICENSE.firefox)。
