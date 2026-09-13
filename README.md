# 修仙门派

> 放置型修仙门派经营模拟 · Web 版
> 由 Godot 4 导出为 WebAssembly，打开浏览器即可游玩，无需安装。

**[▶ 在线试玩](https://yemoren.github.io/xiuxian/)**

---

## 游戏简介

你是一座新立宗门的掌门。招纳弟子、分派职务、经营七峰、炼丹铸器，
看着一代代弟子从练气修至飞升，也看着他们寿终正寝、魂归轮回——
而宗门，会在轮回中一直传承下去。

## 核心玩法

### 弟子
- **十大境界**：练气 → 筑基 → 金丹 → 元婴 → 出窍 → 分神 → 合体 → 渡劫 → 大乘 → 飞升，每境十阶
- **灵根与五行**：金、水、木、火、土、冰、风、雷，影响修炼与生产偏向
- **生命与突破**：境界决定寿元（练气 80 年至飞升不朽），突破有失败与陨落风险

### 七峰经营

| 峰 | 事务 | 产出 |
|---|---|---|
| 镇邪峰 | 除魔卫道 | 战利品、功德 |
| 寻幽峰 | 秘境探索 | 机缘、秘宝 |
| 青芜峰 | 种药 | 灵草 |
| 玄矿峰 | 采掘 | 灵矿 |
| 丹宸峰 | 炼丹 | 丹药 |
| 玄铸峰 | 炼器 | 法宝 |
| 撰书阁 | 撰书 | 功法秘籍 |

### 人员编制
每峰可任命 **峰主**、**副手**，并配置 **外门弟子** 与 **杂役弟子**。
产出效率按职务加权：

| 职务 | 效率权重 |
|---|---|
| 峰主 | 100% |
| 副手 | 50% |
| 外门弟子 | 20% |
| 杂役弟子 | 每人 +5% |

杂役弟子上限：全局 1200 人，单峰最多 200 人。

**产出门槛**：青芜峰 / 玄矿峰需杂役或外门在岗（或有副手、峰主）；
丹宸峰 / 玄铸峰需外门在岗（或有副手、峰主）。未达门槛的峰不产出。

### 其他系统
- **功德建筑**：灵泉、神兽苑、灵雨台等 12 座，跨轮回永久保留
- **事件奇遇**：弟子历练触发随机事件，所得所失的丹药 / 灵草 / 灵矿品阶与其境界匹配
- **法宝与装备**：发冠、衣甲、鞋履、佩饰、武器五槽，荒阶至昊苍阶十级
- **轮回传承**：弟子寿终后转世，宗门积累延续

## 本地运行

Web 版通过 HTTP 加载 wasm，**不能直接双击 `index.html`**（`file://` 协议会失败）。

### 方式一：玩现成的（推荐）

1. 到 [Releases](https://github.com/yemoRen/xiuxian/releases) 下载 `xiuxian-web-v1.0.0.zip`
2. 解压，进入目录
3. 启动本地服务器：

```bash
python serve.py 8130
```

4. 浏览器打开 <http://127.0.0.1:8130/>

Windows 用户也可直接双击 `启动Web版.bat`。

### 方式二：从源码构建

需要 **Godot 4.7.2**（Steam 版亦可，导出模板位于
`steamapps/common/Godot Engine/editor_data/export_templates/`）。

```bash
godot --headless --path . --export-release "Web" "$(pwd)/docs/index.html"
```

产物输出到 `docs/`，该目录即 GitHub Pages 的发布源。

### 本地开发服务器

仓库自带 `build/serve.py`，它会附带
`Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` 响应头，
以兼容本地调试时浏览器的隔离策略要求。

## 项目结构

```
xiuxian/
├── docs/                  # Web 构建产物（GitHub Pages 发布源）
│   ├── index.html
│   ├── index.wasm         # ~39 MB
│   └── index.pck          # 游戏资源包 ~5.5 MB
├── scenes/                # Godot 场景
├── scripts/
│   ├── autoload/          # 全局单例
│   ├── core/              # DataCore（数据） / GameCore（逻辑）
│   ├── ui/                # 界面
│   └── test/              # 无头回归测试
├── assets/                # 美术资源
├── build/serve.py         # 本地静态服务器
├── export_presets.cfg     # 导出预设
└── project.godot
```

## 技术栈

- **引擎**：Godot 4.7.2（GDScript）
- **渲染**：GL Compatibility（WebGL 友好）
- **导出目标**：Web / WebAssembly（无线程构建，因此**不依赖** COOP/COEP 响应头，
  可直接托管在 GitHub Pages 等静态平台上）
- **存档**：`user://` 持久化

## 版本

当前版本 **v1.0.0**，完整历史见 [CHANGELOG.md](CHANGELOG.md)。
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

| 版本 | 日期 | 说明 |
|---|---|---|
| [v1.0.0](https://github.com/yemoRen/xiuxian/releases/tag/v1.0.0) | 2026-09-14 | 首个公开版本，Web 版发布 |

## 说明

本项目是对手机游戏《论如何建立一个修仙门派》玩法的**个人学习与还原实现**，
用于 Godot 引擎与游戏系统设计的学习交流。

- 原作的玩法设计、数值体系与美术创意归原作者所有
- 本项目代码为独立编写，未使用原作的任何素材或代码
- 如原作者或相关权利人提出异议，请及时联系，我会立即下架

---

用 Godot 4 制作 · 开源学习项目
