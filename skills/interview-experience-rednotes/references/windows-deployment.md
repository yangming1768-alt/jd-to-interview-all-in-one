# Windows 一键部署

用户只用自然语言启动 Skill。不要要求用户复制 Node.js、npm、Python、PaddleOCR 或 OpenCLI 命令。

内部入口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File ./scripts/deployment/windows/install.ps1 -CheckOnly -Json
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File ./scripts/deployment/windows/install.ps1 -Json
```

`RemoteSigned` 仅对当前子进程生效。不得调用 `Set-ExecutionPolicy`，不得修改用户或系统的持久化执行策略。

部署目录：

```text
%LOCALAPPDATA%\RednoteInterviewSkill\
├── runtime\
├── models\
├── state\
└── logs\
```

优先复用兼容依赖；缺失时安装到专属目录。不修改系统 PATH，不污染用户现有 Python 环境。

## 进度阶段

```text
[1/8] 正在检查本机环境
[2/8] 正在准备 Node.js
[3/8] 正在安装 OpenCLI
[4/8] 正在准备 OCR 和 Markdown/Word/HTML 导出环境
[5/8] 正在准备 Chrome 和扩展（可能需要用户）
[6/8] 等待登录小红书（需要用户）
[7/8] 正在验证浏览器连接
[8/8] 环境准备完成，继续采集面经
```

常规用户配合仅包括批准安装及官方来源下载、确认添加 Chrome 扩展、登录小红书及输入登录验证码。其他异常只在实际发生时说明。

## 信任边界

禁止读取密码、Cookie、token 或验证码；禁止绕过验证或风控；禁止关闭安全软件；禁止请求永久完全访问；禁止第三方下载站；禁止付费服务；禁止上传图片到第三方 OCR；禁止社交和发布操作；禁止改动用户已有文件；禁止不知情的后台运行。

## Chrome 与登录

Chrome 缺失时从 Google 官方来源下载安装，不设置默认浏览器，不导入历史、密码或收藏夹。扩展只通过官方 Chrome 商店安装，不使用 ZIP 或开发者模式。

在 Browser Bridge 所连接的同一个 Chrome 用户配置中打开小红书。已有登录直接复用；登录失效时才重新提示。自动检测登录完成并继续，不要求用户重新提交 JD。

等待扩展或登录时，以短间隔重复运行 `-CheckOnly -Json`，根据 `overall` 和 `next_action` 区分缺失依赖、等待扩展、等待登录和完全就绪。不要重新执行完整安装，也不要无限轮询；长时间无变化时保持暂停，并提供重新检测或帮助。

## 失败处理

说明完成进度、失败组件、部分环境是否可用，并提供重试、稍后继续、查看技术详情。只修复失败组件，不重装全部依赖。
