# DeepSeek Harness Computer Use v4

这是一个面向 DeepSeek Harness 的 macOS Computer Use 插件，把 Agent Loop 与 macOS 的 Accessibility（AX）树、窗口截图和定向输入连接起来。

## 能力

- 按应用名称、Bundle ID 或 `.app` 路径定位并启动应用。
- 读取应用窗口的 Accessibility 树，返回带 `state_id` 的元素索引。
- 在支持图像输入的模型上返回窗口截图；纯文本模型自动使用 AX 文本。
- 点击、拖拽、滚动、输入文本、按键、设置元素值、执行元素动作和选择文本。
- 每次动作前校验最新状态，避免复用过期的元素索引。
- Helper 只接受固定的白名单子命令，不暴露任意 Shell。
- 涉及敏感文本时使用 Harness 原生 approval 流程。

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

## 目录结构

```text
src/index.js              DeepSeek Harness 插件 Host 代码
cordis.patch.yml          Cordis Bundle 注册补丁
package.json              插件包元数据
helper/pcctl_gui.swift    macOS AXUIElement + CGEvent Helper
scripts/build-helper.sh   Helper 构建脚本
```

## 当前状态

这是一个面向 macOS 的实验性插件。不同 macOS 版本、输入法、应用的 Accessibility 实现可能存在差异，使用前请先在非关键应用中验证。

当前仓库保留原始包配置中的 `UNLICENSED` 声明，公开仓库用于下载和交流；如需允许他人修改、再发布或商业使用，请先补充明确的开源许可证。
