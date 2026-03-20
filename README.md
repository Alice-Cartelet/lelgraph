# Lelegraph

> 一款 iOS 本地加密分发软件

Lelegraph 是一款运行在 iOS 上的本地加密内容管理工具。所有文件均在设备本地完成加密与存储，无需联网，无服务器，数据完全掌握在你手中。

---

## 功能介绍

### 🔐 用户自定义加密密钥
- 在以lelegraph命名的文件中修改allkeystring的字符即可修改加密密钥
- 密钥通过 iOS Keychain 安全存储
- 支持随时在主界面更改密钥

### 📁 文件管理
- 创建、重命名、删除 `.alice` 格式加密文件
- 支持将文件移入「已删除」回收区，或永久删除
- 支持导入外部 `.alice` 文件
- 支持通过系统分享功能导出文件

### 🔒 全面加密保护
- 文件内容采用 **AES-GCM** 加密存储
- 文件名同样经过加密，不暴露任何明文信息
- 加密密钥完全由用户掌控，开发者无法获取

### 🖼️ 富内容支持
- 支持在文件中嵌入文字、图片、GIF 和视频
- 视频文件独立存储于本地 `Videos` 目录

### 🔍 搜索与排序
- 支持按文件名关键词搜索（自动解密后匹配）
- 支持按文件名或修改日期排序，升序/降序可选

---

## 安装 / 构建说明

Lelegraph 使用 Swift + SwiftUI 开发，需通过 Xcode 手动构建安装。

### 环境要求

| 项目 | 要求 |
|------|------|
| Xcode | 15.0 及以上 |
| iOS 部署目标 | iOS 15.5 及以上 |
| Swift | 5.9 及以上 |

### 构建步骤

1. 克隆本仓库

```bash
git clone https://github.com/yourname/lelegraph.git
cd lelegraph
```

2. 用 Xcode 打开项目

```bash
open lelegraph.xcodeproj
```

3. 在 Xcode 中选择你的开发者账号（Signing & Capabilities）

4. 选择目标设备或模拟器，点击 **Run（▶）** 构建并安装

> 无需任何第三方依赖，所有功能均基于系统原生框架（SwiftUI / CryptoKit / AVKit）实现。

---

## 安全说明

- 密钥存储于 iOS **Keychain**，不写入任何明文文件
- 更改密钥后，旧密钥加密的文件将**无法**用新密钥解密，请妥善保管密钥
- 本项目不包含任何网络请求，所有数据仅存储于设备本地

---

## License

```
MIT License

Copyright (c) 2025 lelegraph

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
