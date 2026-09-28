# DeepSeek Harness Computer Use v4

这是一个面向 DeepSeek Harness 的 macOS Computer Use 插件，把 Agent Loop 与 macOS 的 Accessibility（AX）树、窗口截图和定向输入连接起来。

当前源码版本为 **4.0.2**，以 [package.json](./package.json) 为准。变更见[更新日志](./CHANGELOG.md)，发布记录见 [GitHub Releases](https://github.com/liangcaiqiang/deepseek-harness-computer-use/releases)。

## 能力

- 按应用名称、Bundle ID 或 `.app` 路径定位并启动应用。
- 读取应用窗口的 Accessibility 树，返回带 `state_id` 的元素索引。
- 在支持图像输入的模型上返回窗口截图；纯文本模型自动使用 AX 文本。
- 点击、拖拽、滚动、输入文本、按键、设置元素值、执行元素动作和选择文本。
- 元素动作支持 `state_id` 校验；应传入最近观测值，以拒绝已经变化的界面状态。
- Helper 只接受固定的白名单子命令，不暴露任意 Shell。
- 对规则识别出的敏感文本请求 Harness 原生 approval。

## 系统要求

- macOS
- Swift 编译器（安装 Xcode Command Line Tools 即可）
- DeepSeek Harness（`@deepseek-ai/dsh`）
- 已授予运行 Harness 的终端或应用以下权限：
  - 系统设置 → 隐私与安全性 → 辅助功能
  - 系统设置 → 隐私与安全性 → 屏幕录制

## 安装

### 直接从 GitHub 安装

```bash
dsh plugin --profile web add github:liangcaiqiang/deepseek-harness-computer-use
```

### 本地构建 Helper

插件的 Host 代码需要一个固定接口的 macOS Helper。安装后执行：

```bash
git clone https://github.com/liangcaiqiang/deepseek-harness-computer-use.git
cd deepseek-harness-computer-use
./scripts/build-helper.sh
```

默认输出路径为：

```text
~/.dsh/pcctl/pcctl_gui
```

也可以通过环境变量指定其他绝对路径：

```bash
DSH_COMPUTER_USE_HELPER=/absolute/path/pcctl_gui ./scripts/build-helper.sh
```

构建 Helper 后，重启 DeepSeek Harness 或重新加载对应 profile。

## 本地开发安装

```bash
dsh plugin --profile web add file:/absolute/path/deepseek-harness-computer-use
```

如果使用 `npx` 启动 Harness，请把命令中的 `dsh` 替换为：

```bash
npx @deepseek-ai/dsh plugin --profile web add file:/absolute/path/deepseek-harness-computer-use
```

## 安全边界

这个插件只实现窄接口的 GUI 操作，不提供任意命令执行能力。进行不可恢复删除、上传文件、传输敏感数据、修改敏感系统设置或高影响沟通前，应由 Harness 请求用户确认。

Host 对部分认证信息文本有规则检测；其他高影响动作的确认要求由 Agent 遵循工具提示执行。文本检测无法识别所有敏感内容，使用时仍需检查目标应用和实际动作。

## 开发与维护

### 本地检查

在仓库根目录执行：

```bash
node --check src/index.js
bash -n scripts/build-helper.sh
DSH_COMPUTER_USE_HELPER="$(mktemp -d)/pcctl_gui" bash scripts/build-helper.sh
git diff --check
```

编译产物写入临时目录，适合检查 Swift 编译是否通过。Host 的语法检查不加载 Harness 依赖，也不代表插件已通过实际 GUI 操作验证。

### 持续集成

[CI 配置](./.github/workflows/ci.yml) 在推送 `main`、向 `main` 发起 Pull Request 或手动触发时运行：

- Linux：检查 JavaScript 与 Bash 语法、包元数据和必要文件。
- macOS：通过现有构建脚本编译 Swift Helper，检查产物是否可执行。

CI 使用只读仓库权限，第三方 Action 固定到具体提交。真实窗口读取、输入法、截图权限和点击输入仍需在已授权的 Mac 上进行人工验证；CI 不执行桌面操作。

### 问题反馈与发版

提交 Issue 时可选择 Bug 反馈或功能建议模板，并提供版本和复现步骤。日志和截图请先脱敏。

维护改动先记入 `CHANGELOG.md` 的“未发布”。正式发版时统一 `package.json`、更新日志和 Git 标签的版本号，按实际发布日期整理说明；本地检查与对应提交的 CI 通过后，再创建 Release。

## 目录结构

```text
src/index.js              DeepSeek Harness 插件 Host 代码
cordis.patch.yml          Cordis Bundle 注册补丁
package.json              插件包元数据
helper/pcctl_gui.swift    macOS AXUIElement + CGEvent Helper
scripts/build-helper.sh   Helper 构建脚本
CHANGELOG.md              更新日志
.github/workflows/ci.yml  语法检查与 macOS 编译
.github/ISSUE_TEMPLATE/   Bug 反馈和功能建议模板
```

## 当前状态

这是一个面向 macOS 的实验性插件。不同 macOS 版本、输入法、应用的 Accessibility 实现可能存在差异，使用前请先在非关键应用中验证。

本项目采用 [MIT License](./LICENSE)。你可以使用、复制、修改、再发布或商业使用本项目，但需要保留版权声明和许可证文本；软件按“现状”提供，不附带保证。
