// pcctl_gui — 窄接口 macOS GUI 控制 helper（Computer Use）
// 只接受白名单子命令 + JSON 参数；绝不执行任意命令字符串。
// 依赖：Accessibility (AXUIElement) + CoreGraphics (CGEvent)。截图由 Host 层用系统 screencapture 完成。
import ApplicationServices
import AppKit
import CoreGraphics
import Foundation

// MARK: - 工具函数

func json(_ value: Any) -> String {
  if let s = value as? String {
    var escaped = ""
    for scalar in s.unicodeScalars {
      switch scalar.value {
      case 0x22: escaped += "\\\""
      case 0x5C: escaped += "\\\\"
      case 0x08: escaped += "\\b"
      case 0x0C: escaped += "\\f"
      case 0x0A: escaped += "\\n"
      case 0x0D: escaped += "\\r"
      case 0x09: escaped += "\\t"
      case 0x00...0x1F: escaped += String(format: "\\u%04x", scalar.value)
      default: escaped.unicodeScalars.append(scalar)
      }
    }
    return "\"\(escaped)\""
  }
  if let n = value as? Int { return "\(n)" }
  if let n = value as? Double { return String(n) }
  if let b = value as? Bool { return b ? "true" : "false" }
  if let arr = value as? [Any] {
    return "[" + arr.map { json($0) }.joined(separator: ",") + "]"
  }
  if let dict = value as? [String: Any] {
    return "{" + dict.keys.sorted().map { "\(json($0)):\(json(dict[$0] ?? ""))" }.joined(separator: ",") + "}"
  }
  return "null"
}

func fail(_ message: String, code: Int = 1) -> Never {
  print(json(["ok": false, "error": message, "code": code]))
  exit(0)
}

func ok(_ dict: [String: Any]) -> Never {
  var merged: [String: Any] = ["ok": true]
  for (k, v) in dict { merged[k] = v }
  print(json(merged))
  exit(0)
}

// MARK: - 权限

func permissionStatus() {
  let ax = AXIsProcessTrusted()
  let screen = CGPreflightScreenCaptureAccess()
  ok([
    "accessibility": ax,
    "screenRecording": screen,
    "granted": ax && screen,
    "axStatus": ax ? "granted" : "denied",
    "screenRecordingStatus": screen ? "granted" : "denied",
    "hint": ax ? "" : "请前往 系统设置 → 隐私与安全性 → 辅助功能，勾选当前终端/Dashboard 应用",
    "screenHint": screen ? "" : "请前往 系统设置 → 隐私与安全性 → 屏幕录制，勾选当前终端/Dashboard 应用",
  ])
}

// MARK: - 应用列表

func listApps() {
  let ws = NSWorkspace.shared
  let running = ws.runningApplications
  let front = ws.frontmostApplication
  var apps: [[String: Any]] = []
  for app in running {
    guard app.activationPolicy != .prohibited else { continue }
    let pid = app.processIdentifier
    let bundleId = app.bundleIdentifier ?? ""
    let name = app.localizedName ?? bundleId
    apps.append([
      "pid": Int(pid),
      "appId": bundleId,
      "name": name,
      "path": app.bundleURL?.path ?? "",
      "running": true,
      "frontmost": (front?.processIdentifier == pid),
    ])
  }
  ok(["apps": apps])
}

// MARK: - AX 树遍历

final class AXWalker {
  let maxNodes: Int
  var indexCounter = 0
  var nodes: [Int: [String: Any]] = [:]
  var lines: [String] = []

  init(maxNodes: Int = 5000) {
    self.maxNodes = max(100, min(maxNodes, 20_000))
  }

  // 将 CFTypeRef 属性安全转为可输出值
  func attrString(_ el: AXUIElement, _ attr: CFString) -> String {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr, &v) == .success else { return "" }
    return (v as? String) ?? ""
  }

  func attrInt(_ el: AXUIElement, _ attr: CFString) -> Int? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr, &v) == .success else { return nil }
    if let n = v as? Int { return n }
    return nil
  }

  func attrPoint(_ el: AXUIElement, _ attr: CFString) -> CGPoint? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr, &v) == .success else { return nil }
    let axValue = v as! AXValue
    var p = CGPoint.zero
    if AXValueGetType(axValue) == .cgPoint {
      AXValueGetValue(axValue, .cgPoint, &p)
      return p
    }
    return nil
  }

  func attrSize(_ el: AXUIElement, _ attr: CFString) -> CGSize? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr, &v) == .success else { return nil }
    let axValue = v as! AXValue
    var s = CGSize.zero
    if AXValueGetType(axValue) == .cgSize {
      AXValueGetValue(axValue, .cgSize, &s)
      return s
    }
    return nil
  }

  func attrBool(_ el: AXUIElement, _ attr: CFString) -> Bool? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr, &v) == .success else { return nil }
    return (v as? Bool)
  }

  func attrIsSettable(_ el: AXUIElement, _ attr: CFString) -> Bool {
    var b = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(el, attr, &b) == .success else { return false }
    return b.boolValue
  }

  func attrActions(_ el: AXUIElement) -> [String] {
    var arr: CFArray?
    guard AXUIElementCopyActionNames(el, &arr) == .success else { return [] }
    return (arr as? [String]) ?? []
  }

  func walk(_ el: AXUIElement, depth: Int, maxDepth: Int, _ appId: String) {
    guard depth <= maxDepth, indexCounter < maxNodes else { return }
    let index = indexCounter
    indexCounter += 1

    let role = attrString(el, kAXRoleAttribute as CFString)
    let subrole = attrString(el, kAXSubroleAttribute as CFString)
    let title = attrString(el, kAXTitleAttribute as CFString)
    let desc = attrString(el, kAXDescriptionAttribute as CFString)
    let help = attrString(el, kAXHelpAttribute as CFString)
    var value = attrString(el, kAXValueAttribute as CFString)
    let valueSettable = attrIsSettable(el, kAXValueAttribute as CFString)
    let position = attrPoint(el, kAXPositionAttribute as CFString)
    let size = attrSize(el, kAXSizeAttribute as CFString)
    let enabled = attrBool(el, kAXEnabledAttribute as CFString)
    let focused = attrBool(el, kAXFocusedAttribute as CFString)
    let actions = attrActions(el)

    // 截断超长 value 防止爆 token
    if value.count > 200 { value = String(value.prefix(200)) + "…" }

    var node: [String: Any] = [
      "element_index": index,
      "role": role,
      "title": title,
      "description": desc,
      "actions": actions,
    ]
    if !subrole.isEmpty { node["subrole"] = subrole }
    if !help.isEmpty { node["help"] = help }
    if !value.isEmpty { node["value"] = value }
    if valueSettable { node["value_settable"] = true }
    if let p = position { node["x"] = Int(p.x.rounded()); node["y"] = Int(p.y.rounded()) }
    if let s = size { node["width"] = Int(s.width.rounded()); node["height"] = Int(s.height.rounded()) }
    if let e = enabled { node["enabled"] = e }
    if let f = focused { node["focused"] = f }
    nodes[index] = node

    // 文本行：缩进 + 角色 + 标题/描述 + 坐标
    let indent = String(repeating: "  ", count: depth)
    var line = "\(indent)[\(index)] \(role)"
    if !title.isEmpty { line += " \"\(title)\"" }
    if !desc.isEmpty { line += " (\(desc))" }
    if !value.isEmpty { line += " = \(value)" }
    if let p = position, let s = size {
      line += " @\(Int(p.x.rounded())),\(Int(p.y.rounded())) \(Int(s.width.rounded()))x\(Int(s.height.rounded()))"
    }
    if !actions.isEmpty { line += " {\(actions.joined(separator: ","))}" }
    lines.append(line)

    // 子元素
    var children: CFTypeRef?
    if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children) == .success {
      if let arr = children as? [AXUIElement] {
        for child in arr {
          walk(child, depth: depth + 1, maxDepth: maxDepth, appId)
        }
      }
    }
  }
}

// 通过 PID 获取应用 AX 根
func appElement(_ pid: Int) -> AXUIElement? {
  guard pid > 0 else { return nil }
  return AXUIElementCreateApplication(pid_t(pid))
}

// 从 PID 查找应用（供 appId 解析）
func pidFromAppId(_ appId: String) -> Int? {
  let ws = NSWorkspace.shared
  for app in ws.runningApplications {
    if app.bundleIdentifier == appId { return Int(app.processIdentifier) }
    if app.localizedName == appId { return Int(app.processIdentifier) }
  }
  return nil
}

// 将输入事件严格定向到指定应用，避免按键落到意外的前台窗口。
func activateApp(pid: Int) {
  guard pid > 0 else { fail("activate 需要 pid") }
  guard let app = NSRunningApplication(processIdentifier: pid_t(pid)) else {
    fail("找不到 PID=\(pid) 的运行中应用")
  }
  guard app.activate(options: [.activateIgnoringOtherApps]) else {
    fail("无法激活应用 \(app.localizedName ?? String(pid))")
  }
  // 优先 Raise 一个现有窗口；某些应用即使进程已激活，窗口仍会留在后面。
  let axApp = AXUIElementCreateApplication(pid_t(pid))
  var windowsValue: CFTypeRef?
  if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
     let windows = windowsValue as? [AXUIElement], let first = windows.first {
    AXUIElementPerformAction(first, kAXRaiseAction as CFString)
  }
  // 等待 NSWorkspace 确认前台归属；遇到竞争激活时重复一次请求。
  for _ in 0..<10 {
    if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid_t(pid) {
      usleep(150_000)
      return
    }
    app.activate(options: [.activateIgnoringOtherApps])
    usleep(100_000)
  }
  fail("应用激活超时：\(app.localizedName ?? String(pid))")
}

// 返回目标应用最可能的主窗口，供 Host 层执行窗口级截图。
func windowInfo(pid: Int) {
  guard pid > 0 else { fail("window_info 需要 pid") }
  let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
  guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    fail("无法读取窗口列表")
  }
  let candidates = raw.compactMap { info -> [String: Any]? in
    guard let ownerPid = info[kCGWindowOwnerPID as String] as? Int, ownerPid == pid else { return nil }
    let layer = info[kCGWindowLayer as String] as? Int ?? 0
    guard layer == 0 else { return nil }
    guard let number = info[kCGWindowNumber as String] as? Int,
          let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
          let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { return nil }
    let area = Int(max(0, bounds.width) * max(0, bounds.height))
    guard area > 10_000 else { return nil }
    return [
      "windowId": number,
      "title": info[kCGWindowName as String] as? String ?? "",
      "x": Int(bounds.origin.x.rounded()),
      "y": Int(bounds.origin.y.rounded()),
      "width": Int(bounds.width.rounded()),
      "height": Int(bounds.height.rounded()),
      "area": area,
    ]
  }.sorted { ($0["area"] as? Int ?? 0) > ($1["area"] as? Int ?? 0) }
  guard let first = candidates.first else { fail("目标应用没有可截图的屏幕窗口") }
  ok(["window": first, "windowCount": candidates.count])
}

// MARK: - app_state

func appState(pid: Int, depth: Int, maxNodes: Int) {
  guard let app = appElement(pid) else { fail("无法创建应用 AX 元素（PID=\(pid)）") }
  let walker = AXWalker(maxNodes: maxNodes)
  walker.walk(app, depth: 0, maxDepth: depth, "")
  let treeText = walker.lines.joined(separator: "\n")
  // 按 index 升序输出（nodes 是字典，需排序保证稳定顺序）
  let elements = walker.nodes.keys.sorted().compactMap { walker.nodes[$0] }
  ok([
    "pid": pid,
    "elementCount": elements.count,
    "truncated": walker.indexCounter >= walker.maxNodes,
    "elements": elements,
    "treeText": treeText,
  ])
}

// 元素动作名（全局可用）
func elementActions(_ el: AXUIElement) -> [String] {
  var arr: CFArray?
  guard AXUIElementCopyActionNames(el, &arr) == .success else { return [] }
  return (arr as? [String]) ?? []
}

// MARK: - 从 AX 树中按 index 取元素

// 缓存最近一次 app_state 的元素映射（每次操作前由 Host 强制刷新）
var lastAppPid: Int = -1
var lastAppElements: [Int: AXUIElement] = [:]
var _elementCounter = 0

func refreshElements(pid: Int) {
  if pid == lastAppPid { return }
  lastAppPid = pid
  lastAppElements.removeAll()
  _elementCounter = 0
  guard let app = appElement(pid) else { return }
  collectElements(app)
}

func collectElements(_ el: AXUIElement) {
  let idx = _elementCounter
  _elementCounter += 1
  lastAppElements[idx] = el
  var children: CFTypeRef?
  if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &children) == .success {
    if let arr = children as? [AXUIElement] {
      for child in arr { collectElements(child) }
    }
  }
}

func elementForIndex(pid: Int, index: Int) -> AXUIElement? {
  refreshElements(pid: pid)
  return lastAppElements[index]
}

// 调试：验证某 index 在 collectElements 路径下命中的元素角色/标题（用于一致性校验）
func debugIndex(pid: Int, index: Int) {
  guard let el = elementForIndex(pid: pid, index: index) else { fail("index \(index) 无效") }
  var role: CFTypeRef?
  AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
  var title: CFTypeRef?
  AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &title)
  var val: CFTypeRef?
  AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &val)
  var pv: CFTypeRef?
  var p = CGPoint.zero
  if AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pv) == .success {
    AXValueGetValue(pv as! AXValue, .cgPoint, &p)
  }
  var sv: CFTypeRef?
  var s = CGSize.zero
  if AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sv) == .success {
    AXValueGetValue(sv as! AXValue, .cgSize, &s)
  }
  ok([
    "index": index,
    "role": role as? String ?? "?",
    "title": title as? String ?? "",
    "value": val as? String ?? "",
    "x": Int(p.x.rounded()), "y": Int(p.y.rounded()),
    "width": Int(s.width.rounded()), "height": Int(s.height.rounded()),
  ])
}

// 执行 AX 动作
func performAction(el: AXUIElement, action: String) -> Bool {
  return AXUIElementPerformAction(el, action as CFString) == .success
}

// MARK: - CGEvent 输入

func cgMouseClick(x: CGFloat, y: CGFloat, button: CGMouseButton, count: Int) {
  let source = CGEventSource(stateID: .hidSystemState)
  for i in 0..<count {
    let downType: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
    let upType: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
    let p = CGPoint(x: x, y: y)
    let down = CGEvent(mouseEventSource: source, mouseType: downType, mouseCursorPosition: p, mouseButton: button)
    down?.setIntegerValueField(.mouseEventClickState, value: Int64(i + 1))
    down?.post(tap: .cghidEventTap)
    let up = CGEvent(mouseEventSource: source, mouseType: upType, mouseCursorPosition: p, mouseButton: button)
    up?.setIntegerValueField(.mouseEventClickState, value: Int64(i + 1))
    up?.post(tap: .cghidEventTap)
    if count > 1 { usleep(80_000) }
  }
}

func cgMouseMove(x: CGFloat, y: CGFloat) {
  CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)?.post(tap: .cghidEventTap)
}

func cgMouseDrag(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat) {
  let source = CGEventSource(stateID: .hidSystemState)
  let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: x1, y: y1), mouseButton: .left)
  down?.post(tap: .cghidEventTap)
  // 分步移动模拟拖拽
  let steps = 20
  for i in 1...steps {
    let t = CGFloat(i) / CGFloat(steps)
    let px = x1 + (x2 - x1) * t
    let py = y1 + (y2 - y1) * t
    let move = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: CGPoint(x: px, y: py), mouseButton: .left)
    move?.post(tap: .cghidEventTap)
    usleep(10_000)
  }
  let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: CGPoint(x: x2, y: y2), mouseButton: .left)
  up?.post(tap: .cghidEventTap)
}

func cgScroll(x: CGFloat, y: CGFloat, dx: Int32, dy: Int32) {
  let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)
  move?.post(tap: .cghidEventTap)
  let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: dx, wheel3: 0)
  scroll?.post(tap: .cghidEventTap)
}

// 按键映射
let keyCodeMap: [String: CGKeyCode] = [
  "return": 36, "enter": 36, "tab": 48, "space": 49, "escape": 53, "esc": 53,
  "delete": 51, "backspace": 51, "forwarddelete": 117,
  "up": 126, "down": 125, "left": 123, "right": 124,
  "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
  "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34,
  "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12,
  "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
  "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
  "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98,
  "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
  "comma": 43, "period": 47, "slash": 44, "backslash": 42, "semicolon": 41, "quote": 39,
  "minus": 27, "equal": 24, "bracketleft": 33, "bracketright": 30,
]

let modifierMap: [String: CGEventFlags] = [
  "command": .maskCommand, "cmd": .maskCommand,
  "control": .maskControl, "ctrl": .maskControl,
  "shift": .maskShift,
  "option": .maskAlternate, "alt": .maskAlternate, "opt": .maskAlternate,
  "fn": .maskSecondaryFn,
]

let modifierKeyCodeMap: [String: CGKeyCode] = [
  "command": 55, "cmd": 55,
  "control": 59, "ctrl": 59,
  "shift": 56,
  "option": 58, "alt": 58, "opt": 58,
  "fn": 63,
]

func pressKey(key: String, mods: [String], holdMs: Int) {
  guard let code = keyCodeMap[key.lowercased()] else {
    fail("未知按键: \(key)。支持的按键: return,tab,escape,space,delete,up,down,left,right,home,end,pageup,pagedown,a-z,0-9,f1-f12,comma,period,slash,semicolon,quote,minus,equal")
  }
  var flags: CGEventFlags = []
  var modifierCodes: [CGKeyCode] = []
  var seen = Set<CGKeyCode>()
  for m in mods {
    let low = m.lowercased()
    guard let f = modifierMap[low] else {
      fail("未知修饰键: \(m)。支持: command,control,shift,option,fn")
    }
    flags.insert(f)
    if let k = modifierKeyCodeMap[low], !seen.contains(k) {
      modifierCodes.append(k)
      seen.insert(k)
    }
  }
  let source = CGEventSource(stateID: .hidSystemState)

  // 主键按下与释放之间的最短保持时间：取 holdMs 与 20ms 的较大值
  let primaryHoldUs = useconds_t(max(holdMs, 20) * 1000)
  // 各事件阶段间隔：10-20ms
  let stageUs: useconds_t = 15_000 // 15ms，处于 10–20ms 区间内

  if !modifierCodes.isEmpty {
    // 依次按下修饰键（每个修饰键之间 15ms 间隔）
    for mk in modifierCodes {
      let md = CGEvent(keyboardEventSource: source, virtualKey: mk, keyDown: true)
      md?.flags = flags
      md?.post(tap: .cghidEventTap)
      usleep(stageUs)
    }
    // 按下主键
    let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
    down?.flags = flags
    down?.post(tap: .cghidEventTap)
    // 主键保持：至少 20ms
    usleep(primaryHoldUs)
    // 释放主键
    let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    up?.flags = flags
    up?.post(tap: .cghidEventTap)
    // 主键释放与修饰键释放之间 15ms 间隔
    usleep(stageUs)
    // 依次释放修饰键（逆序）
    for mk in modifierCodes.reversed() {
      let mu = CGEvent(keyboardEventSource: source, virtualKey: mk, keyDown: false)
      mu?.flags = []
      mu?.post(tap: .cghidEventTap)
      usleep(stageUs)
    }
  } else {
    // 无修饰键：按下主键
    let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
    down?.post(tap: .cghidEventTap)
    // 主键保持：至少 20ms
    usleep(primaryHoldUs)
    // 释放主键
    let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    up?.post(tap: .cghidEventTap)
  }
  // 最后再等 20ms，确保事件被目标应用消费
  usleep(20_000)
}

func typeText(_ text: String) {
  // 逐字符发送 Unicode，并为每次按下/抬起保留事件处理时间。
  // 整段文本塞进一个瞬时事件时，部分 macOS 控件会直接丢弃输入。
  let source = CGEventSource(stateID: .hidSystemState)
  for character in text {
    let utf16 = Array(String(character).utf16)
    let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
    down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
    down?.post(tap: .cghidEventTap)
    usleep(20_000)

    let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
    up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
    up?.post(tap: .cghidEventTap)
    usleep(20_000)
  }
  usleep(20_000)
}

// MARK: - 安全校验

func validateText(_ text: String) -> String {
  // 敏感数据由 Host 的上下文安全策略和 Harness 原生 approval 服务处理。
  // Helper 只负责长度边界，避免把语义判断错误地固化在底层输入驱动中。
  if text.count > 5000 { fail("文本过长（\(text.count) 字符），上限 5000") }
  return text
}

func validateCoord(_ x: CGFloat, _ y: CGFloat) {
  let screens = NSScreen.screens
  guard let main = screens.first else { return }
  let frame = main.frame
  // 允许略微越界（菜单栏上方），但拒绝明显无效
  if x < -200 || x > frame.width + 200 || y < -200 || y > frame.height + 200 {
    fail("坐标越界: (\(Int(x)), \(Int(y)))，屏幕范围 \(Int(frame.width))x\(Int(frame.height))")
  }
}

// MARK: - 主入口

func main() {
  let args = CommandLine.arguments
  guard args.count >= 2 else { fail("用法: pcctl_gui <subcommand> '<json-args>'") }
  let sub = args[1]

  // 解析 JSON 参数
  var params: [String: Any] = [:]
  if args.count >= 3 {
    let jsonStr = args[2]
    if let data = jsonStr.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      params = obj
    } else {
      fail("参数不是合法 JSON")
    }
  }

  switch sub {
  case "permission":
    permissionStatus()
  case "list_apps":
    listApps()
  case "activate":
    let pid = params["pid"] as? Int ?? -1
    activateApp(pid: pid)
    ok(["activated": pid])
  case "window_info":
    let pid = params["pid"] as? Int ?? -1
    windowInfo(pid: pid)
  case "app_state":
    let pid = params["pid"] as? Int ?? -1
    let maxNodes = params["maxNodes"] as? Int ?? 5000
    // 全深度遍历（与 collectElements 保持一致，保证 element_index 对齐）
    let depth = 500
    guard pid > 0 else { fail("app_state 需要 pid") }
    appState(pid: pid, depth: depth, maxNodes: maxNodes)
  case "debug_index":
    let pid = params["pid"] as? Int ?? -1
    let index = params["index"] as? Int ?? -1
    guard pid > 0 else { fail("debug_index 需要 pid") }
    debugIndex(pid: pid, index: index)
  case "click":
    let buttonStr = params["button"] as? String ?? "left"
    let button: CGMouseButton = (buttonStr == "right") ? .right : .left
    let count = max(1, min(params["count"] as? Int ?? 1, 3))
    if let index = params["index"] as? Int, let pid = params["pid"] as? Int {
      // 1. 激活目标应用，确保 CGEvent 落到目标窗口
      if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
        app.activate(options: [.activateIgnoringOtherApps])
        usleep(200000) // 等待 200ms 让应用真正到前台
      }
      guard let el = elementForIndex(pid: pid, index: index) else { fail("element_index \(index) 无效（状态可能已过期，请重新调用 app_state）") }
      // 2. 通过 AX 设置目标元素为焦点
      let _ = AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, true as CFTypeRef)
      usleep(50000) // 等待 50ms 让 AX 焦点生效
      var p = CGPoint.zero
      var s = CGSize.zero
      var pv: CFTypeRef?
      guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pv) == .success,
            AXValueGetValue(pv as! AXValue, .cgPoint, &p) else { fail("元素没有位置属性") }
      var sv: CFTypeRef?
      if AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sv) == .success {
        AXValueGetValue(sv as! AXValue, .cgSize, &s)
      }
      let cx = p.x + s.width / 2
      let cy = p.y + s.height / 2
      validateCoord(cx, cy)
      // 3. 发送鼠标点击
      cgMouseClick(x: cx, y: cy, button: button, count: count)
      usleep(50000) // 等待 50ms 让点击生效
      ok(["clicked": "element_index \(index)", "x": Int(cx.rounded()), "y": Int(cy.rounded()), "button": buttonStr, "count": count])
    } else if let x = params["x"] as? Double, let y = params["y"] as? Double {
      validateCoord(CGFloat(x), CGFloat(y))
      cgMouseClick(x: CGFloat(x), y: CGFloat(y), button: button, count: count)
      ok(["clicked": "coordinate", "x": Int(x.rounded()), "y": Int(y.rounded()), "button": buttonStr, "count": count])
    } else {
      fail("click 需要 index+pid 或 x/y")
    }
  case "drag":
    if let x1 = params["x1"] as? Double, let y1 = params["y1"] as? Double,
       let x2 = params["x2"] as? Double, let y2 = params["y2"] as? Double {
      validateCoord(CGFloat(x1), CGFloat(y1))
      validateCoord(CGFloat(x2), CGFloat(y2))
      cgMouseDrag(x1: CGFloat(x1), y1: CGFloat(y1), x2: CGFloat(x2), y2: CGFloat(y2))
      ok(["dragged": [x1, y1, x2, y2]])
    } else {
      fail("drag 需要 x1,y1,x2,y2")
    }
  case "scroll":
    let dx = params["dx"] as? Int32 ?? 0
    let dy = params["dy"] as? Int32 ?? 0
    if let x = params["x"] as? Double, let y = params["y"] as? Double {
      validateCoord(CGFloat(x), CGFloat(y))
      cgScroll(x: CGFloat(x), y: CGFloat(y), dx: dx, dy: dy)
      ok(["scrolled": [x, y, dx, dy]])
    } else if let index = params["index"] as? Int, let pid = params["pid"] as? Int {
      guard let el = elementForIndex(pid: pid, index: index) else { fail("element_index \(index) 无效") }
      var p = CGPoint.zero, s = CGSize.zero
      var pv: CFTypeRef?
      if AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pv) == .success { AXValueGetValue(pv as! AXValue, .cgPoint, &p) }
      var sv: CFTypeRef?
      if AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sv) == .success { AXValueGetValue(sv as! AXValue, .cgSize, &s) }
      let cx = p.x + s.width / 2, cy = p.y + s.height / 2
      cgScroll(x: cx, y: cy, dx: dx, dy: dy)
      ok(["scrolled": ["element_index": index]])
    } else {
      fail("scroll 需要 x/y+dx/dy 或 index+pid+dx/dy")
    }
  case "type":
    let text = validateText(params["text"] as? String ?? "")
    if let pid = params["pid"] as? Int, pid > 0 { activateApp(pid: pid) }
    typeText(text)
    ok(["typed": text])
  case "press":
    let key = params["key"] as? String ?? ""
    let mods = params["mods"] as? [String] ?? []
    let holdMs = max(0, min(params["holdMs"] as? Int ?? 0, 5000))
    if let pid = params["pid"] as? Int, pid > 0 { activateApp(pid: pid) }
    pressKey(key: key, mods: mods, holdMs: holdMs)
    ok(["pressed": key, "mods": mods])
  case "set_value":
    let index = params["index"] as? Int ?? -1
    let pid = params["pid"] as? Int ?? -1
    let value = validateText(params["value"] as? String ?? "")
    guard let el = elementForIndex(pid: pid, index: index) else { fail("element_index \(index) 无效") }
    let setErr = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, value as CFTypeRef)
    guard setErr == .success else { fail("设置值失败: \(setErr.rawValue)") }
    ok(["set_value": value, "element_index": index])
  case "secondary_action":
    let index = params["index"] as? Int ?? -1
    let pid = params["pid"] as? Int ?? -1
    let action = params["action"] as? String ?? ""
    guard let el = elementForIndex(pid: pid, index: index) else { fail("element_index \(index) 无效") }
    // 只执行元素明确暴露的动作
    let available = elementActions(el)
    guard available.contains(action) else { fail("元素未暴露动作 \(action)。可用动作: \(available.joined(separator: ","))") }
    guard performAction(el: el, action: action) else { fail("执行动作 \(action) 失败") }
    ok(["secondary_action": action, "element_index": index])
  case "select_text":
    let index = params["index"] as? Int ?? -1
    let pid = params["pid"] as? Int ?? -1
    let mode = params["mode"] as? String ?? "all" // all | range
    guard let el = elementForIndex(pid: pid, index: index) else { fail("element_index \(index) 无效") }
    if mode == "all" {
      // 设置 AXSelectedTextRange 覆盖全部（0..count）
      var v: CFTypeRef?
      guard AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &v) == .success else { fail("无法读取文本值") }
      let text = (v as? String) ?? ""
      var range = CFRange(location: 0, length: CFIndex(text.utf16.count))
      let axRange = AXValueCreate(.cfRange, &range)
      let err = AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, axRange!)
      guard err == .success else { fail("选择文本失败: \(err.rawValue)") }
      ok(["selected_text": text, "mode": "all"])
    } else {
      let start = params["start"] as? Int ?? 0
      let end = params["end"] as? Int ?? 0
      var range = CFRange(location: CFIndex(start), length: CFIndex(max(0, end - start)))
      let axRange = AXValueCreate(.cfRange, &range)
      let err = AXUIElementSetAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, axRange!)
      guard err == .success else { fail("选择文本失败: \(err.rawValue)") }
      ok(["selected_text": "range \(start)..\(end)", "mode": "range"])
    }
  default:
    fail("未知子命令: \(sub)。允许: permission,list_apps,activate,window_info,app_state,debug_index,click,drag,scroll,type,press,set_value,secondary_action,select_text")
  }
}

main()
