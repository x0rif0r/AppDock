<h1 align="center">AppDock</h1>

<p align="center"><strong>您的应用，您的资料库。</strong><br>保存 IPA → 创建预设 → 通过 USB 安装。</p>

<p align="center">
  <a href="https://github.com/x0rif0r/AppDock/releases"><img alt="Release" src="https://img.shields.io/github/v/release/x0rif0r/AppDock?include_prereleases&style=flat-square&color=6366f1"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple-Silicon-111827?style=flat-square">
  <a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-6366f1?style=flat-square"></a>
</p>

[Русский](README.md) · [English](README.en.md) · [简体中文](README.zh-CN.md)

**在 Mac 上管理您的 iPhone 和 iPad 应用资料库。**

AppDock 将 Apple ID 购买记录、通过 ipatool 下载 IPA、本地或 NAS 存储，以及 USB 安装队列整合在一个 macOS 应用中。选择账号、查找应用、保存 IPA，然后安装到指定设备。

[详细指南（俄语）](docs/USER_GUIDE.md) · [下载](https://github.com/x0rif0r/AppDock/releases) · [反馈问题](https://github.com/x0rif0r/AppDock/issues) · [MIT 许可证](LICENSE)

作者：**x0rif0r**。**2.1.2** 是适用于 **Apple Silicon 和 macOS 14 及以上版本**的预发布版本。本文件为中文说明；当前应用界面、详细指南和社区目录仍为俄语。下文保留实际按钮的俄语名称，并附上中文解释。

## 界面截图

真实界面使用演示数据。截图中的账号、设备及相关信息均为虚构，不是个人资料库。

![ 资料库与安装 ](docs/images/library.png)

<details>
<summary>购买记录与账号 · 任务队列 · 设备</summary>

### 购买记录与账号

![购买记录与账号](docs/images/accounts.png)

### 任务队列

![任务队列](docs/images/queue.png)

### 设备

![设备](docs/images/devices.png)

</details>

## 兼容性

iOS 26.6.2：已完成 EatsRate 的 USB 安装及启动流程测试。**iOS 27：用户反馈可以使用；尚未在该版本上独立验证完整流程。** 每个 IPA 的兼容性及许可证可用性仍需单独检查。

## 功能

- 带图标和搜索功能的 App Store 购买记录，可切换您自己的账号。
- 在 Mac 原生窗口中输入密码，并按需输入双重认证（2FA）验证码。
- 已保存的 IPA 显示为灰色；版本卡片在元数据可用时显示许可证所属账号。
- 应用分组、不同变体、版本、App Store ID 和 Bundle ID。
- 分类与自定义预设，方便配置设备。
- 下载和安装按队列依次执行，支持暂停、调整顺序、进度百分比和预计剩余时间。
- 本地与 NAS 资料库；本地缓存可在 NAS 断开时使用已缓存文件。
- 选择 USB 设备，查看型号、iOS 版本、可获取的设备信息和安装历史。
- 在支持的设备上通过 USB 获取壁纸，或手动选择图片。

## 安装

1. 从 [Releases](https://github.com/x0rif0r/AppDock/releases) 下载 `AppDock-2.1.2-macOS-arm64.pkg`。安装器将 **AppDock.app 安装到 /Applications**，不安装后台服务，也不运行依赖安装脚本。
2. 使用 [Homebrew](https://brew.sh) 安装外部工具：

   ```sh
   brew install ipatool libimobiledevice ideviceinstaller
   ```

3. 检查您安装的 ipatool 是否支持购买记录：

   ```sh
   ipatool list-purchases --help
   ```

   没有此命令时，购买记录功能无法使用。请按需更新 ipatool；命令是否可用取决于安装的构建版本。

4. 从“应用程序”打开 AppDock。应用使用 ad hoc 签名；安装包未经 Developer ID 签名或 Apple 公证。macOS 可能要求在系统设置中允许此特定应用运行。请勿全局关闭 Gatekeeper。

本发行版不包含外部 CLI 工具或第三方 IPA，也不支持 Intel Mac。将 `SHA256SUMS.txt` 与安装包下载到同一文件夹后，可在该文件夹执行：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

更新时，先完成队列并退出 AppDock，再安装新版本。用户资料库和历史记录独立于应用保存。待执行任务只存在于当前应用会话中。

## 开始使用

### Apple ID 与购买记录

打开 **Мои приложения App Store → Другой аккаунт…**（我的 App Store 应用 → 其他账号），输入 Apple ID、密码，并在提示时输入 2FA 验证码。使用 iPhone **“媒体与购买项目”**中的账号；它可能与 iCloud 账号不同。AppDock 不会更改系统的 iCloud 账号。

购买记录分页面加载，并按账号分别缓存。Apple 返回的记录中没有列出的已保存 IPA，可以作为“已保存 IPA”补充显示。可以查看其他账号的缓存记录，但下载需要实际登录该账号。执行任务或队列非空时，账号切换不可用。

请检查 **Активен**（当前已登录）或 **Сессия подтверждена**（会话已确认），不要只看下拉框中的账号名称。2FA 提示表示 ipatool 正在等待验证码，并不证明通知或短信已经送达。取消登录不会激活新账号。

**退出登录：**点击 **Выйти**。这会撤销当前 ipatool 会话，但保留 IPA 和缓存记录。若不希望某个未登录账号继续出现在列表中，选择它并点击 **Убрать аккаунт из списка**（从列表移除账号）。重新登录会恢复该账号及其缓存记录。执行任务或队列非空时不能退出。

找到应用后，选择分类并点击 **Скачать**（下载），或将多个应用加入队列。购买记录中，已为同一账号保存的 IPA 显示为灰色。可以通过资料库中的版本菜单更新或替换 IPA；替换时旧文件会保留为备份。

### 本地与 NAS 存储

打开 **Хранилище**（存储），选择 Local 或 NAS，然后选择文件夹。使用 NAS 时，先通过 Finder 挂载网络共享，例如 SMB。下载在 Mac 上进行，并保存到所选文件夹；没有远程服务器模式。

两个模式各自记住所选文件夹。切换文件夹不会自动迁移旧资料库。安装前，IPA 会复制到本地缓存并接受检查。NAS 断开后仍可使用此前缓存的副本。

### 通过 USB 安装

1. 连接 iPhone，解锁设备并确认信任 Mac。
2. 选择目标设备及应用或预设。
3. 点击 **Установить на iPhone**（安装到 iPhone）。任务会绑定所选设备。
4. 查看队列；暂停会在当前操作完成后生效。

安装历史按设备保存。默认跳过设备上已存在相同或更新版本的应用。启用 **Переустановить такую же версию**（重新安装相同版本）后，可再次传输相同版本，无需先删除应用。设备上更新的版本始终会被跳过；此选项会随安装任务保存。

剩余时间只是估算。下载达到 100% 后仍需检查 IPA 并将其加入资料库。

## 保存旧 iPhone 上的应用

打开 **Устройства и история**（设备与历史），选择 iPhone，再打开 **Сохранить с iPhone**（从 iPhone 保存）。通过 USB 读取已安装应用，选择已解析出 ID 的应用，将下载加入队列。

AppDock 通过精确的 Bundle ID，将设备上的应用与所选账号的购买记录、您的资料库及内置社区目录进行匹配。如果设备提供数字 ItemID，也会使用它。未确定或有冲突的 ID 不会自动下载。Apple 提供的下载版本可能不同于旧手机上安装的版本。关闭 **Только найденные ID**（仅显示已解析 ID）可查看尚未匹配的应用。

下载完成后，点击 **К установке · N сохранённых**（准备安装 · 已保存 N 个）。此操作只选择当前筛选列表中的已保存 IPA，并以设备名和搜索内容创建预设。点击前即可看到数量；搜索一个应用不会选择手机上的其他应用。连接目标 iPhone，在主窗口选择它，再开始安装。完整资料库仍可在主窗口查看。

选择另一个缓存账号时，会打开已填写账号标识的登录窗口。ipatool 只有一个当前会话，AppDock 不会在后台恢复所有账号的独立会话。为未登录账号请求下载后，可在登录成功时将任务加入队列。AppDock 不保存密码。

**Проверить App Store**（检查 App Store）仅查询俄罗斯地区的公开商店，不检查许可证，也不能证明应用在全球下架。对于已知 ID、在该地区商店找不到且尚未收录的应用，**Предложить в каталог…** 会打开 GitHub Issue 草稿。请补充官方来源并自行提交；草稿不包含账号、序列号或 UDID。

**Забыть устройство**（忘记设备）在确认后移除设备卡片及其安装历史，不影响手机或 IPA。仍连接着的设备会在下次扫描时重新出现。

## Apple 许可证与限制

购买记录不能保证已下架应用仍可重新下载。Apple 可能拒绝提供许可证或文件。AppDock 不会自动购买应用、移除 DRM、重新签名 IPA，或在 Apple ID 之间转移许可证。

安装后的应用可能要求登录其许可证所属账号。IPA 元数据包含此信息时，版本卡片会显示该账号。一个账号购买应用，并不授权另一个账号免费激活。

CRC、SHA-256、App Store ID 和 Bundle ID 检查用于发现损坏和信息不匹配，不能证明银行应用的真实性。成功安装也不能保证应用可以启动、服务可用，或兼容某个 iOS 版本。图标来自用户 IPA 或已核对的 Apple 元数据；缺失时显示占位图。

## 设备图片

设备卡片显示已保存的图片。若希望显示真正的锁屏时钟和小组件，请在 iPhone 上截图，传到 Mac，并在设备菜单选择 **Экран блокировки → Импортировать снимок**（锁定屏幕 → 导入截图）。

USB 截图需要 screenshotr 服务。在测试的 iPhone 上，没有开发者镜像时该服务不可用。AppDock 不会启用开发者模式或更改手机设置。预览是已保存图片，并非实时画面。获取壁纸是另一项功能，不包含锁屏时钟或小组件。

## 数据与隐私

- 密码和 2FA 验证码通过 stdin/PTY 传递给本地辅助程序，不通过进程参数传递。AppDock 不会将其写入文件或日志。
- ipatool 在 macOS 钥匙串中保存授权会话；只有一个当前会话，并非为所有账号保存独立会话。
- 账号邮箱、购买记录、设备信息、图片和缓存**保存在本地**的 `~/Library/Application Support/IPAOrganizer`。旧路径保留用于兼容早期版本。
- IPA 和资料库元数据位于所选 Local/NAS 文件夹中。元数据可能包含许可证所属 Apple ID；请据此配置网络文件夹权限。
- 应用使用 Apple 服务、App Store 下载和外部 CLI 工具，没有自建服务器。
- 本仓库和发行包不包含用户 IPA、账号、购买记录、设备报告、壁纸或令牌。

## 常见问题

| 问题 | 检查方法 |
| --- | --- |
| `license is required` 或应用不可用 | 检查实际登录的 Apple ID 及此前是否获取过该应用。即使有许可证，下架应用也可能无法重新下载。 |
| iPhone 要求购买账号 | 查看 IPA 版本卡片中的 Apple ID。许可证不会转移到其他账号。 |
| 找不到连接的设备 | 检查线缆、解锁状态、信任确认和 libimobiledevice。 |
| 没有购买记录 | 检查 ipatool 的 `list-purchases` 支持和有效登录。Apple 的列表可能遗漏已下架应用。 |
| 出错后队列停止 | 处理原因，在队列中点击继续，并重新添加失败的下载任务。 |
| NAS 断开 | 重新挂载共享，或使用此前的本地缓存。 |
| 获取壁纸失败 | 支持情况取决于 iOS；可以手动选择图片。 |

反馈问题时，请提供 AppDock 版本、macOS 版本和复现步骤。**不要附上密码、2FA 验证码、令牌、IPA 或未脱敏的个人日志。**

## 从源码构建

需要 Apple Silicon Mac、macOS 14 及以上版本和 Xcode Command Line Tools。

```sh
git clone https://github.com/x0rif0r/AppDock.git
cd AppDock
zsh build.sh
open build/AppDock.app
```

应用使用 SwiftUI/AppKit 和两个项目自有的 C 辅助程序。外部 CLI 依赖需单独安装。生成安装包：

```sh
zsh scripts/package.sh
```

产物位于 `dist/`，安装包旁会生成校验文件。

## 测试与项目状态

```sh
python3 -m unittest discover -s Tests -v
```

五项测试覆盖模拟 CLI 的认证传输（2FA、拒绝、取消和敏感信息脱敏）、精确 ID 冲突，以及重新安装时防止降级的逻辑。

2026 年 10 月 12 日，使用 EatsRate 1.3 完成了实际流程测试：读取 iPhone 应用列表 → 匹配 ID → 使用有效许可证下载 → 检查 IPA → 保存预设 → 通过 USB 实际重新安装 → 确认设备版本及安装历史。用户确认应用启动时没有要求其他 Apple ID。测试使用了一台已有设备；尚未单独验证迁移到另一台干净的 iPhone。已在连接的 iPhone 上测试壁纸获取。NAS 需针对具体存储设备测试。尚未覆盖所有设备和 iOS 版本，因此本版本仍为预发布。

## 社区目录

[应用对应表（俄语）](catalog/README.md) 包含已知 ID、来源和替代名称。这些条目用于进一步验证，不代表账号拥有许可证或一定可以下载。通过 [Issue](https://github.com/x0rif0r/AppDock/issues/new?template=app.yml) 或 Pull Request 提交应用，规则见 [CONTRIBUTING.md](CONTRIBUTING.md)。

目录随应用打包，用于精确匹配 Bundle ID。更新会包含在后续构建中，并非持续从 GitHub 同步。目前包含 76 个数字 ID 和单独的未确定列表。StoreMed 和 SmartMed 根据官方来源归入 MEDSI；Grok Bot 已排除，官方 Grok 保留。Filter T 对应的 App Store 名称为 Filtercare Techs。

## 作者与许可证

© 2026 **x0rif0r**。项目自有代码采用 [MIT 许可证](LICENSE)。

外部项目：[ipatool](https://github.com/majd/ipatool)、[libimobiledevice](https://github.com/libimobiledevice/libimobiledevice)、[ideviceinstaller](https://github.com/libimobiledevice/ideviceinstaller) 和 [DeviceKit](https://github.com/devicekit/DeviceKit)。用途和许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，完整文本位于 [Licenses](Licenses)。AppDock 的许可证不适用于第三方应用或 Apple ID 许可证。
