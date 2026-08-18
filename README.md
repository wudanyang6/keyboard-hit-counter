# Keyboard Hit Counter

常驻 macOS 菜单栏的按键计数工具：记录每个前台应用的键盘敲击次数，按天累计并本地持久化。热路径使用 listenOnly 事件 tap + 无锁原子计数，对输入零阻塞。

## 构建与运行

```bash
make run      # 构建 release 并打包 .app 后启动
make app      # 只打包 build/KeyboardHitCounter.app
make test     # 运行单元测试
```

## 权限

首次运行需在「系统设置 → 隐私与安全性 → 辅助功能」中勾选本应用，之后自动开始计数。计数数据保存在 `~/Library/Application Support/KeyboardHitCounter/counts.json`。