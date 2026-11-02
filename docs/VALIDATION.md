# 1.0.0 本地验证记录

验证日期：2026-11-02。环境：macOS 27.2、Apple Silicon、Swift 6.4.2、Command Line Tools。

- `MC_INTEGRATION_TRASH=1 swift run MacCleanChecks`：21 项检查通过，0 跳过，0 失败。
- `./scripts/build.sh`：成功生成 Universal 2 应用与 DMG。
- `lipo -info`：确认包含 `arm64`、`x86_64`。
- `codesign --verify --deep --strict`：应用签名结构检查通过；签名类型为 ad-hoc，无 Developer ID，无公证。
- `hdiutil verify`：镜像校验通过。
- DMG 只读挂载检查：包含应用、Applications 快捷链接和中文安装说明；挂载后的应用签名验证通过。
- Apple Silicon 应用启动并渲染概览与实际临时文件夹扫描结果：通过。
- `arch -x86_64` 经 Rosetta 启动并渲染概览：通过。未在 Intel 硬件验证。

回归检查覆盖目录汇总与隐藏文件、符号链接、硬链接去重、取消扫描、缺失目录、SHA-256 已知向量、重复内容与文件变化、旧文件规则、目录中新文件保护、运行中应用缓存、受保护路径、父级符号链接、路径边界与重叠、应用关联数据精确匹配、损坏恢复记录、目录子项变更、重复组保留副本变化以及取消清理。

真实废纸篓往返测试仅操作程序创建的临时夹具，并验证恢复时不会覆盖同名文件；未清理用户现有数据。

未验证 macOS 13–26 上的实机兼容性、大规模数百万文件目录性能、所有第三方云盘占位文件实现与所有应用的关联数据归属。系统与文件权限会影响统计结果；Intel 切片通过 Rosetta 启动不等同于 Intel 实机验证。

当前工具链在交叉编译时对缺失的 x86_64 Swift Compatibility Packs 静态库和若干 Xcode 搜索目录发出警告，链接成功；这也意味着旧系统实测仍有必要。具体支持与限制见 README。
