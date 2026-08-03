# OpenCLI 小红书调用约束

## 允许的命令

通过 `scripts/invoke_opencli.ps1` 调用：

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File ./scripts/invoke_opencli.ps1 xiaohongshu search "关键词" --limit 10 -f json
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File ./scripts/invoke_opencli.ps1 xiaohongshu note "完整签名URL" -f json
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File ./scripts/invoke_opencli.ps1 xiaohongshu download "完整签名URL" --output "目标图片目录"
```

仅使用 `search`、`note`、`download`。MVP 不使用 `comments`、`feed`、`saved`、`liked`、`notifications`、`creator-*`、`follow` 或 `publish`。

## 签名 URL

`note` 和 `download` 必须使用搜索结果返回的完整 URL。保留 `xsec_token` 及其他查询参数。不要只保存 note ID，也不要自行拼接 token。

PowerShell 中 URL 可能含有 `&`。必须把命令参数作为数组传给进程，不得把 URL 拼进命令字符串，也不得使用 `Invoke-Expression`。

## 环境检查

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File ./scripts/deployment/windows/install.ps1 -CheckOnly -Json
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File ./scripts/invoke_opencli.ps1 doctor
```

`RemoteSigned` 只覆盖当前 PowerShell 子进程，不修改用户持久化执行策略。

Browser Bridge 需要 Chrome 正在运行、扩展已启用，并使用同一个已登录小红书的 Chrome 用户配置。

## 退出状态

- `0`：成功
- `66`：结果为空；尝试下一个搜索词
- `69`：Browser Bridge 未连接；检查 Chrome 和扩展
- `75`：超时；有限重试并降低频率
- `77`：需要登录；暂停并让用户登录
- `78`：配置错误；重新运行环境检查
- `130`：用户中断；保存当前进度后停止

其他非零状态把 stderr 写入技术日志，但只向用户提供简短说明。

## 访问节奏

- 逐个搜索词执行。
- 逐个候选读取详情。
- 不并发批量打开帖子。
- 不进行高频刷新。
- 出现验证码、访问限制或安全验证时立即停止，不绕过。

## 官方参考

- OpenCLI 项目：https://github.com/jackwener/OpenCLI
- 小红书适配器：https://opencli.info/docs/adapters/browser/xiaohongshu.html
- Browser Bridge：https://opencli.info/docs/guide/browser-bridge.html
