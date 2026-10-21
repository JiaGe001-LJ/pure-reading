# 洁阅读 Pure Reading

轻量、跨平台的文本与漫画阅读器（Android 首发，代码结构已为 iOS / 鸿蒙留好扩展位）。
设计初衷，对于pdf漫画的分割。
mobi因版权问题，没有录入。
可用第三方将其改成PDF再录入。

## 功能

- **书架 + 我的设置**：极简双 Tab 主界面。
- **TXT 文本阅读**：自动识别编码（UTF-8 / GBK / UTF-16 带 BOM）、逐页排版、
  上下滑动 + 左右点击翻页、章节识别与跳转、字号调节、阅读进度记忆。
- **图片 / 漫画阅读**：JPG / PNG 等，左右翻页、双指缩放、双击放大；
  支持一次多选导入整本漫画（按文件名自然排序）。
- **PDF 阅读 / PDF 漫画**：PDF 每页转图阅读（系统 PdfRenderer 渲染，无额外
  原生库），同样支持翻页、缩放与「漫画双页分割」；漫画 PDF（一张竖版双页
  合图）可一键切成两张横版单页按正确顺序阅读。
- **漫画双页分割（核心特色）**
  - 把一张“竖版双页合图”（左半第 1 页、右半第 2 页）切成两张横版单页；
  - 配置一：左旋 90°，左半在前（第 1 页）；
  - 配置二：右旋 90°，右半在前（第 1 页）；
  - 配置三：不旋转，左半在前（第 1 页），保持原方向直接分割；
  - 分割线可选“二分之一线”或“自动检测”（识别页间亮缝 / 书脊阴影）；
  - 配置可扩展：设置页可新增任意“分割线方式 + 旋转方向 + 页面顺序”组合。
- **主题**：跟随系统 / 浅色 / 深色。
- **字体**：正文 12–32 号可调，阅读器内快捷调节。
- **文件管理**：本地文件导入（系统文件选择器，无需存储权限），或从网址下载导入。
- **捐赠支持**：设置页展示微信收款二维码。

## 技术栈

- Flutter 3.47.7（Dart 3.13），Material 3
- 依赖极简：provider、path_provider、file_picker、image（图片分割处理）、
  fast_gbk（GBK 解码）、pdfx（PDF 渲染，Android 端为系统 PdfRenderer）
- 设置与书架均以本地 JSON 文件持久化（settings.json / books.json），无数据库依赖
- 纯本地运行，无云平台依赖，APK 体积小、内存占用低
- PDF 阅读与漫画分割全程走内存字节（渲染 → 分割 → 显示），无中间文件，
  页缓存（最近 8 页）+ 同页双半页共享一次渲染与分割

## 已知问题与修复记录

- **v1.0.1 → v1.0.2**
  - PDF 打不开（pdfx 2.11.0 Android 手动渲染的 `PdfPageAlreadyClosedException`）：
    本地 patch 包 `packages/pdfx_patched`（每次取页重新注册、渲染后由调用方关闭），
    pubspec 以 `dependency_overrides` 指向，不依赖上游修复。
  - 翻页被 InteractiveViewer 抢手势：未放大时 `panEnabled/scaleEnabled` 均关闭，
    放大后（双击 / 双指）才启用，保证滑动翻页与缩放互不干扰。
  - release 版分割页偶发 broken 图标：PDF 页显示由 `Image.file` 改为
    `Image.memory`（渲染结果直接进内存缓存），消除文件 IO 与解码时序问题。
  - 页码与显示错位（恢复进度后分割开启定位错误）：改用稳定的
    `PageController` + 显式 `jumpToPage`，移除 PageStorageKey 干扰。
  - 分割计算重复：同一 PDF 页的两个半页共享一次渲染 + 一次分割。
- **v1.0.2 → v1.0.3**
  - 新增预置「配置三 · 不旋转」：保持原方向直接分割（左半为第 1 页），
    适合想保留原始画面方向查看半页的场景；分割核心与显示（BoxFit.contain
    自动适配竖版窄条）无需改动，配置列表动态生效。
- **v1.0.3 → v1.0.4**
  - 分割配置重排：配置一·不旋转（默认）/ 配置二·左旋90° / 配置三·右旋90°。
  - TXT 打开提速：去掉自动目录解析，改为增量排版（先出少量页，后台补完）。
  - TXT 阅读设置：字号滑杆 / 字体（默认·衬线·等宽）/ 翻页方向。
  - 支持按文件夹整目录导入漫画（递归扫描，自然排序）。
  - 图片阅读器大图降采样（cacheWidth），避免大图卡死与内存溢出。
  - 关于页更新版本号与功能说明。
- **v1.0.4 → v1.0.5**
  - 翻页动画（翻书 / 淡入）移除，改为「翻页方向：左右 / 上下」，
    更省资源、更实用；方向切换后自动跳回当前页。
  - TXT 排版算法重写：字符宽度估算 + 行级切分，O(n) 无逐段 TextPainter
    测量，2MB 级文本秒开（实测 3MB 文本 <1 秒排完，拼接等于原文）。
  - PDF / 图片阅读器同步支持翻页方向切换。

## 构建

```bash
flutter pub get
flutter test          # 核心分割逻辑单元测试
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

> 国内网络建议设置镜像：
> `PUB_HOSTED_URL=https://pub.flutter-io.cn`
> `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`
> 本项目 android/gradle/wrapper 已指向腾讯 Gradle 镜像，
> android/settings.gradle.kts 已加入阿里云 Maven 镜像。

## 目录结构

```
lib/
  main.dart                # 入口
  app.dart                 # MaterialApp + 主题
  models/                  # Book / SplitConfig / AppSettings
  state/app_state.dart     # 全局状态
  services/
    storage_service.dart   # 书架与设置的持久化
    import_service.dart    # 本地文件 / 网址导入
    text_loader.dart       # 编码检测 + 章节解析 + 分页排版
    image_splitter.dart    # 漫画双页分割核心（含自动检测分割线）
    pdf_service.dart       # PDF 渲染（系统 PdfRenderer，串行渲染）
  screens/
    home_screen.dart       # 书架 / 我的设置 双 Tab
    bookshelf_screen.dart  # 书架
    settings_screen.dart   # 设置
    split_config_screen.dart # 分割配置管理（可扩展）
    txt_reader_screen.dart # 文本阅读器
    image_reader_screen.dart # 图片/漫画阅读器
    pdf_reader_screen.dart # PDF 阅读器（渲染转图 + 分割配置）
    donation_screen.dart   # 捐赠
  widgets/book_cover.dart  # 封面
```

## 后续计划（预留）

- iOS：`flutter create --platforms ios` 补齐工程后可直接构建。
- 鸿蒙：接入 OpenHarmony 的 Flutter 移植分支（flutter_flutter），
  增加 ohos/ 目录即可；业务代码无需改动。
- 分割配置已做成数据驱动模型，可继续增加“不旋转”“自定义分割线偏移”等配置。
