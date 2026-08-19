# StockBar

StockBar 是一个轻量的 macOS 菜单栏 A 股行情应用。菜单栏只显示一个小图标，点击后即可查看上证指数和自选股的名称、实时涨跌幅与股价。

![macOS](https://img.shields.io/badge/macOS-10.14%2B-black)
![Architecture](https://img.shields.io/badge/architecture-Universal%202-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## 功能

- 上证指数固定显示在列表第一行；
- 自选股同时显示名称、涨跌幅和股价；
- 交易时段每 5 秒刷新，非交易时段每 60 秒检查一次；
- 在列表底部直接输入六位 A 股代码并按回车添加；
- 鼠标移到自选股行时显示删除按钮；
- 直接拖动股票行调整自选股顺序；
- 支持腾讯财经、东方财富以及自动故障切换；
- 支持系统开机启动；
- Intel 与 Apple Silicon Universal 2；
- 在带 Touch Bar 的 Mac 上保留 Touch Bar 行情，无 Touch Bar 的 Mac 会自动隐藏相关功能。

> StockBar 使用非官方公开行情端点，并在支持的机器上使用 macOS 私有 Touch Bar API。它适合个人查看行情，不构成投资建议，也不适合提交 Mac App Store。

## 下载与安装

1. 打开仓库右侧的 **Releases**，下载最新版 `StockBar-版本号.dmg`。
2. 双击 DMG，把 `StockBar.app` 拖入 `Applications`。
3. 从“应用程序”启动 StockBar。应用没有 Dock 图标，启动后会出现在屏幕顶部菜单栏。

当前免费发布版使用临时签名，没有 Apple Developer ID 公证。macOS 首次打开时可能阻止运行：

1. 先尝试打开一次 StockBar；
2. 打开“系统设置 → 隐私与安全性”；
3. 找到 StockBar 的拦截提示，点击“仍要打开”；
4. 再次确认打开。

只应从本仓库 Release 下载，并可使用 Release 中的 `SHA256SUMS` 校验文件完整性。

## 使用说明

### 查看行情

点击菜单栏的趋势图标即可展开列表：

- 红色代表上涨；
- 绿色代表下跌；
- 上证指数固定在第一行，不能删除或移动；
- 菜单顶部显示最后更新时间和实际使用的行情源。

### 添加自选股

在“添加自选股”右侧输入六位 A 股代码，然后按回车。例如：

- `600519`：贵州茅台；
- `000001`：平安银行；
- `300750`：宁德时代；
- `920002`：北交所股票示例。

支持上海、深圳和北京证券交易所的六位股票代码。部分 macOS 版本的系统菜单窗口可能不显示输入插入光标，但点击输入框后键盘输入和回车添加仍然有效。

### 删除与排序

- 把鼠标移到某只自选股行，点击最右侧圆形叉号即可删除；
- 按住自选股整行并拖到另一行，松开后保存新顺序；
- 上证指数不会显示删除按钮，也不参与拖动排序。

### 行情源

菜单中的“行情源”提供三个选项：

- **自动切换**：优先腾讯财经，失败或数据不完整时使用东方财富补齐；
- **腾讯财经**：固定使用腾讯行情；
- **东方财富**：固定使用东方财富行情。

请求失败时会保留最后一次成功行情。选择“立即刷新行情”可以手动请求最新数据。

### 开机启动

勾选菜单中的“开机启动”即可通过 macOS `SMAppService` 注册登录项。系统可能要求在“系统设置 → 通用 → 登录项与扩展”中批准。

建议先把 StockBar 放入 `/Applications`，再开启此选项。应用升级或移动后会尝试把登录项重新注册到当前路径。

### Touch Bar

StockBar 会先通过 IOKit 检测物理 Touch Bar：

- 没有 Touch Bar 时，不加载私有框架、不启动 watchdog，也不显示 Touch Bar 菜单；
- 检测到 Touch Bar 且系统接口可用时，保留原来的跨 App 行情栏和恢复按钮；
- Touch Bar 接口属于 macOS 私有 API，未来系统版本可能改变其行为。

## 隐私与网络

StockBar 不包含广告、账号系统、埋点、遥测或崩溃上报。

保存在本机的数据：

- 自选股代码与顺序；
- 行情源选择；
- 开机启动注册路径。

这些设置位于当前用户的 `dev.talon.stockbar` 偏好设置域，不会写入 GitHub 仓库，也不会由应用主动上传。

网络请求仅用于获取行情，会把公开股票代码发送到所选行情源：

- 腾讯财经：`qt.gtimg.cn`；
- 东方财富：`push2delay.eastmoney.com` 的行情节点。

应用不读取通讯录、照片、邮件、浏览器数据、剪贴板或其他个人文件，也不需要 API Key。

## 卸载

1. 在 StockBar 菜单中关闭“开机启动”；
2. 选择“退出 StockBar”；
3. 把 `/Applications/StockBar.app` 移到废纸篓。

如需同时清除本地自选股和设置，可在终端执行：

```bash
defaults delete dev.talon.stockbar
```

## 从源码构建

依赖：

- macOS；
- Apple Clang / Command Line Tools；
- `make`、`lipo`、`codesign` 和 `hdiutil`；
- 无第三方代码依赖。

构建 Universal 2 应用：

```bash
make
```

产物位于：

```text
build/StockBar.app
```

启动开发构建：

```bash
make run
```

运行硬件检测和真实行情冒烟测试：

```bash
make smoke-test
```

生成 DMG 和 SHA-256 校验文件：

```bash
make release
```

发布产物位于 `dist/`。

## 技术说明

- Objective-C、AppKit、Foundation、IOKit；
- x86_64 最低目标 macOS 10.14；
- arm64 最低目标 macOS 11；
- `NSURLSession` 批量请求行情；
- `NSUserDefaults` 保存本地配置；
- `SMAppService.mainAppService` 管理登录项；
- 私有 Touch Bar 符号通过 `dlopen`、`dlsym` 和 Objective-C runtime 动态探测，缺失时不会产生链接崩溃。

## License

[MIT](LICENSE)
