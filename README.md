# AI 创作者助手 (xhs_creator)

AI 驱动的虚拟试穿与内容创作工具 — 上传服装和人物照片，AI 自动生成试穿效果图和小红书风格文案。

## 架构

```
┌──────────────┐     HTTP/REST      ┌──────────────┐
│  Flutter App │ ◄────────────────► │  ai-service   │
│   (客户端)    │                    │  (Python API) │
│  Port: any   │                    │  Port: 3001   │
└──────────────┘                    └───────┬──────┘
                                            │
                                     ┌──────▼──────┐
                                     │  阿里百炼 API │
                                     │  DashScope   │
                                     └─────────────┘
```

- **app/** — Flutter 移动应用（Android），提供创作、编辑、浏览等 UI
- **ai-service/** — Python FastAPI 后端，封装阿里百炼 AI 对接（虚拟试衣、图片编辑、文案生成）、用户认证、数据存储
- **IDM-VTON/** — 参考模型实现
- **test_phone.py** — 手机端真机全流程自动化测试脚本

## 前提条件

| 组件 | 要求 |
|------|------|
| Python | 3.10+ |
| Flutter | 3.27+ (SDK ^3.11.4) |
| Android SDK | API 21+，Android Studio 或命令行工具 |
| 模拟器/设备 | Android Emulator 或真机 |
| 阿里百炼账号 | 开通 DashScope API（虚拟试衣、图片编辑、文案生成） |

## 快速开始

### 1. 启动后端

```bash
cd ai-service
pip install -r requirements.txt

# 创建 .env 文件，填入 API Key
cp .env.example .env
# 编辑 .env：DASHSCOPE_API_KEY=sk-xxx

python main.py
```

服务默认运行在 `http://0.0.0.0:3001`。

### 2. 启动前端

```bash
cd app
flutter pub get
flutter build apk --release    # 打包 APK
# 或
flutter run -d <device_id>     # 直接运行调试
```

### 3. 配置服务端地址

应用首次启动时进入登录页：

1. 在登录页点击「**服务端设置**」→「展开」
2. 输入后端地址，例如 `http://<你的电脑IP>:3001`
3. 点击「保存」
4. 切换至 **注册** 模式，输入用户名和密码完成注册

IP 地址会持久化保存在本地，下次启动无需重新配置。

## 环境变量

`ai-service/.env`：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `DASHSCOPE_API_KEY` | 阿里百炼 API Key（必填） | — |
| `AITRYON_MODEL` | 虚拟试衣模型 | `aitryon` |
| `QWEN_MODEL` | 文案生成模型 | `qwen-plus` |
| `IMAGE_EDIT_MODEL` | 图片编辑模型 | `wanx2.1-imageedit` |
| `PORT` | 服务端口 | `3001` |
| `PUBLIC_BASE_URL` | OSS 回调和结果图片的公网地址前缀 | — |

> 本地测试时不填 `PUBLIC_BASE_URL` 即可（图片通过 DashScope 内置 OSS 上传通道处理）。

## 运行测试

### 模拟器集成测试（emulator-5556）

```bash
cd app
# 模拟器默认使用 http://10.0.2.2:3001（映射到宿主机 localhost:3001）
flutter test integration_test/app_test.dart --name '完整功能测试' -d emulator-5556
```

测试覆盖（24 阶段）：
- 账号密码注册 / 登录
- 图片上传（服装 + 人物）
- AI 虚拟试穿生成（aitryon）
- AI 文案生成（qwen-plus）
- 预览 / 保存 / 浏览帖子
- **长按文字复制**（SelectableText 验证）
- **长按图片保存到相册**（Gal → onLongPress）
- **分享面板**（share_plus → 图文分享）
- 从历史记录进入编辑
- 文案编辑（聊天界面 + SelectableText + AI 响应）
- 图片编辑（输入指令 → wanx2.1-imageedit）
- 模拟重装（清除 SharedPreferences）
- 数据持久化验证（重装后帖子一致，可查看可编辑）

### 真机 WiFi 全流程测试

```bash
# 1. 确保后端已启动、手机与电脑在同一 WiFi 网络
cd ai-service && python main.py

# 2. 通过 USB 安装测试 APK（仅用于安装和发送测试指令）
cd app
adb -s <device_id> install build/app/outputs/flutter-apk/app-debug.apk

# 3. 设置环境变量为后端 WiFi 地址，然后运行测试
#    测试会模拟用户在登录页「服务端设置」中输入该地址
# Windows PowerShell:
$env:TEST_SERVER_URL = "http://<你的电脑IP>:3001"
# macOS / Linux:
export TEST_SERVER_URL="http://<你的电脑IP>:3001"

flutter test integration_test/app_test.dart --name '完整功能测试' -d <device_id>
```

> 测试 URL 通过环境变量 `TEST_SERVER_URL` 配置，默认使用 `http://10.0.2.2:3001`（模拟器本地映射）。测试会模拟用户在登录页的「服务端设置」中输入该 URL。

## 项目结构

```
├── ai-service/           # Python 后端
│   ├── main.py           # FastAPI 主入口
│   ├── requirements.txt  # Python 依赖
│   ├── .env.example      # 环境变量模板
│   ├── data/             # 本地 JSON 数据库（运行时生成）
│   ├── uploads/          # 用户上传 / AI 生成的图片（运行时生成）
│   └── test_oss.py       # OSS 上传测试脚本
├── app/                  # Flutter 移动应用
│   ├── lib/              # Dart 源代码
│   │   ├── main.dart     # 应用入口
│   │   ├── config/       # 配置
│   │   ├── models/       # 数据模型
│   │   ├── providers/    # 状态管理 (Provider)
│   │   ├── screens/      # 页面 (create, edit, home, login, preview, settings)
│   │   ├── services/     # API / 存储服务
│   │   └── theme/        # 主题
│   ├── integration_test/ # 集成测试
│   │   └── app_test.dart # 全流程测试
│   ├── test/             # 单元 / Widget 测试
│   └── pubspec.yaml      # Flutter 依赖
├── IDM-VTON/             # 参考模型
├── test_phone.py         # 真机全流程自动化测试脚本
├── .gitignore
└── README.md
```

## 技术栈

| 层级 | 技术 |
|------|------|
| 前端框架 | Flutter 3.27+ (Dart) |
| 状态管理 | Provider |
| 后端框架 | FastAPI (Python) |
| AI 服务 | 阿里百炼 DashScope |
| 虚拟试衣 | aitryon |
| 文案生成 | qwen-plus |
| 图片编辑 | wanx2.1-imageedit |
| 图片存储 | DashScope OSS 上传通道 |
| 认证 | SHA-256 + Salt 密码哈希 / UUID Token |
| 本地存储 | SharedPreferences (token, 服务端地址) |
| 复制分享 | SelectableText + share_plus + gal |
| 测试 | Flutter Integration Test + Python 真机自动化 |

## 常见问题

**Q: 登录页一直显示"加载中"？**

A: 检查后端是否已启动（`http://localhost:3001`），以及登录页「服务端设置」中的地址是否正确。

**Q: 虚拟试衣/文案生成失败？**

A: 检查 `.env` 中的 `DASHSCOPE_API_KEY` 是否正确，阿里百炼账户是否已开通对应模型的调用权限。

**Q: 图片上传/编辑提示失败？**

A: 无需额外配置 OSS 凭证，图片通过 DashScope 内置 OSS 上传通道处理。确保 API Key 有效即可。

**Q: 测试跑一半断连？**

A: Flutter 集成测试通过 WebSocket 与模拟器通信，长时间运行偶有断连。重新运行即可（模拟器和后端保持运行状态）。

**Q: 数据库在哪里？**

A: `ai-service/data/db.json` — 运行时生成的 JSON 文件，已加入 `.gitignore`。首次启动自动创建。