# 第三方素材说明

本项目只有一个第三方资源：**中文字体 Noto Sans SC**（SIL Open Font License 1.1，可自由再发布）。
其余美术与音效仍然全部是项目自己生成的。

## 字体（唯一第三方资源）

- 文件：`assets/fonts/NotoSansSC-Regular.otf`（Noto Sans SC Regular，约 8.3MB）
- 许可证：`assets/fonts/OFL.txt`（SIL Open Font License 1.1）
- 来源：Noto CJK 项目（Google / Adobe，https://github.com/notofonts/noto-cjk）
- 为什么要它：Web 版本在浏览器里没有系统字体可用，不内嵌中文字体就会出现「豆腐块」；
  桌面版也因此不再依赖 macOS 的字体回退，三个平台字形完全一致。
- 使用范围：只作为界面与游戏内文字字体，未做任何修改（OFL 允许嵌入与再发布）。

## 美术

老板、锅（五种）、办公室背景、特效、界面全部由项目自己的 GDScript 用 Godot 原生绘制 API
（`_draw` / `Control` / `Theme`）实时绘制，`icon.svg` 也是本项目自己写的矢量图。
没有使用任何外部图片、贴图、图标或字体文件。

界面中文由上面这个内嵌字体渲染，桌面与 Web 一致。

## 音效

`assets/audio/` 下的 21 个 WAV 全部由 `tools/generate_sfx.gd` 在本地**程序合成**
（正弦 / 方波 / 三角波 / 锯齿 / 噪声 + 包络 + 一阶低通），没有采样、没有下载任何音频素材。
重新生成：

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tools/generate_sfx.tscn
```

## 引擎

项目使用 Godot Engine 4.7（MIT 许可证）。游戏本身不附带引擎二进制。

## 与《老板来了》项目的关系

《疯狂甩锅》是独立项目：不复制、不引用、不依赖 `/Users/.../TowerDefense` 下的任何运行时脚本或素材。
玩法思路相同，但代码、数值、场景、界面与音效都是为这个独立游戏重新实现的。
