# Paste++

[中文](#中文) · [English](#english)

## 中文

Paste++ 是一个 macOS 菜单栏工具，用来搜索、收藏和粘贴复制过的文本。

### 下载

从 [GitHub Releases](https://github.com/YzxUpUp/paste-plus-plus/releases/latest) 下载 macOS 通用版 ZIP，解压后将 `Paste++.app` 拖到「应用程序」。支持 macOS 14 或更新版本，适用于 Apple 芯片和 Intel Mac。

下载版未经 Apple 公证。如果首次打开时系统提示无法验证开发者，请确认下载来源和发布页上的 SHA-256 后，参阅 [Apple 的打开说明](https://support.apple.com/zh-cn/102445)。

### 构建和启动

需要 macOS 14 或更新版本，以及带有 Swift 6 的 Xcode Command Line Tools。在项目目录运行：

```bash
./build.sh
open 'Paste++.app'
```

脚本会为当前电脑的架构构建应用。启动后，从 macOS 菜单栏打开 Paste++。

有 Developer ID Application 签名证书时，可运行 `PASTEPLUSPLUS_SIGN_IDENTITY='Developer ID Application: …' ./build.sh`。连续版本使用同一开发团队的签名和相同的应用标识，macOS 可以沿用辅助功能授权。从临时签名切换到证书签名时，需要为新签名授权一次。

### 使用方法

1. 复制文本后，按 **⌘⇧V** 打开查询窗口，也可以从菜单栏选择「打开历史记录」。
2. 「历史」默认保留最近 100 次文本复制。历史页左下角显示当前条数和上限，满额时提示新记录会替换最旧的记录。输入关键词搜索，按 **↑ / ↓** 选择，再按回车或双击粘贴。按 **Esc** 关闭窗口。
3. 在「历史」中选中一条记录，点击「收藏选中项」。点击「收藏」标签即可搜索和粘贴收藏。收藏条数不限，清空历史或新记录覆盖旧历史时，收藏仍会保留。

点击查询窗口右上角的齿轮，或在菜单栏选择「设置…」，可以自定义快捷键、切换外观、调整历史记录上限或清空历史。外观默认跟随系统，历史记录上限可设置为 100 到 9999 条。

首次读取剪贴板时，macOS 可能会弹出权限提示。要让 Paste++ 自动粘贴到原应用，在齿轮菜单中选择「授权自动粘贴…」，并在「系统设置 → 隐私与安全性 → 辅助功能」允许 Paste++。应用会检测授权并恢复自动粘贴，必要时自动重新打开。可在同一个菜单点「关闭自动粘贴」，之后选中记录时自行按 **⌘V** 粘贴。临时签名的版本更新后如果需要重新授权，请移除旧的辅助功能条目并添加当前的 `Paste++.app`。

历史和收藏保存在本机的 `~/Library/Application Support/Paste++/`。应用会跳过剪贴板上明确标记为保密的内容。

### 许可证

[MIT](LICENSE)

## English

Paste++ is a macOS menu bar app for searching, saving, and pasting text from your clipboard history. The app's interface is currently in Chinese. The Chinese labels below match the controls you'll see.

### Download

Get the universal macOS ZIP from [GitHub Releases](https://github.com/YzxUpUp/paste-plus-plus/releases/latest), extract it, and drag `Paste++.app` to Applications. Paste++ supports macOS 14 or later on Apple silicon and Intel Macs.

The download is not notarized by Apple. If macOS can't verify the developer on first launch, check the download source and the SHA-256 on the release page, then see [Apple's instructions for opening the app](https://support.apple.com/en-us/102445).

### Build and launch

You need macOS 14 or later and Xcode Command Line Tools with Swift 6. Run these commands from the project directory.

```bash
./build.sh
open 'Paste++.app'
```

The script builds the app for your Mac's architecture. Once it launches, look for Paste++ in the menu bar.

If you have a Developer ID Application signing identity, build with `PASTEPLUSPLUS_SIGN_IDENTITY='Developer ID Application: …' ./build.sh`. macOS can retain Accessibility permission across builds signed by the same development team with the same bundle identifier. Switching from ad-hoc signing requires a fresh grant.

### Use Paste++

1. After copying text, press **⌘⇧V** to open the search window. You can also select **Open History** (「打开历史记录」) from the menu bar.
2. The **History** tab (「历史」) keeps the last 100 text copies by default. The bottom left shows the current count and limit. When history is full, new entries replace the oldest ones. Enter a search term, use **↑ / ↓** to select an entry, then press **Return** or double-click to paste. Press **Esc** to close the window.
3. To save an entry, select it in History and click **Save Selected Item** (「收藏选中项」). The **Favorites** tab (「收藏」) lets you search and paste saved entries. Favorites have no count limit and stay saved when you clear history or older entries roll off.

Click the gear in the upper-right corner of the search window, or choose **Settings** (「设置…」) from the menu bar, to customize the shortcut, change the appearance, set the history limit, or clear history. Appearance follows the system by default. You can set the history limit to any whole number from 100 to 9,999.

macOS may ask for clipboard access the first time Paste++ reads it. To paste into the previous app automatically, choose **Authorize Auto-Paste** (「授权自动粘贴…」) from the gear menu and allow Paste++ under **System Settings → Privacy & Security → Accessibility**. Paste++ checks for the grant and reopens itself if macOS requires a fresh process. Choose **Disable Auto-Paste** (「关闭自动粘贴」) to paste manually with **⌘V** after selecting an entry. If an ad-hoc signed update needs a fresh grant, remove the old Accessibility entry and add the current `Paste++.app`.

History and favorites are stored locally in `~/Library/Application Support/Paste++/`. Paste++ skips clipboard items explicitly marked as confidential.

### License

[MIT](LICENSE)
