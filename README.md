# 我的掌上仙宗

> 放置型仙宗经营模拟 · Web 版
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
| 杂役弟子 | 每人 +1%（单峰上限 100 人、全宗上限 300 人） |

杂役弟子上限：全宗 300 人，单峰最多 100 人（需自行分配）。

**产出门槛**：青芜峰 / 玄矿峰需杂役或外门在岗（或有副手、峰主）；
丹宸峰 / 玄铸峰需外门在岗（或有副手、峰主）。未达门槛的峰不产出。

### 其他系统
- **功德建筑**：灵泉、神兽苑、灵雨台等 12 座，跨轮回永久保留
- **事件奇遇**：弟子历练触发随机事件，所得所失的丹药 / 灵草 / 灵矿品阶与其境界匹配
- **法宝与装备**：发冠、衣甲、鞋履、佩饰、武器五槽，荒阶至昊苍阶十级
- **战斗与损耗**：镇魔峰除魔、寻幽峰探秘会按战果令参战成员承受「损耗」（当前武力折损），
  随时间缓慢恢复；秘境挫折还可能留下「伤势」，暂时压低恢复上限，可用「还春丹」消解
- **轮回传承**：弟子寿终后转世，宗门积累延续
- **移动端适配**：UI 与字体针对手机竖屏放大，支持手指上下拖动页面；
  Web 版建宗时点击输入按钮即可填写掌门姓名与宗派名。
  「建立宗门」弹窗已适配手机宽高——内容在屏内纵向滚动、长文案自动折行，不再超出屏幕或被截断

## 本地运行

Web 版通过 HTTP 加载 wasm，**不能直接双击 `index.html`**（`file://` 协议会失败）。

### 方式一：玩现成的（推荐）

1. 到 [Releases](https://github.com/yemoRen/xiuxian/releases) 下载 `xiuxian-web-v1.0.10.zip`
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

### 部署到 Vercel

仓库已内置 `vercel.json`，**导入即部署，无需手动配置**。

1. 打开 [vercel.com/new](https://vercel.com/new)，用 GitHub 账号登录
2. 找到 `yemoRen/xiuxian` 仓库，点 **Import**
   （若看不到，先在 GitHub 侧授权 Vercel 访问该仓库）
3. 配置按下表填写，其余保持默认：

   | 配置项 | 值 |
   |---|---|
   | Framework Preset | **Other** |
   | Build & Output Settings → Build Command | **留空**（纯静态，无需构建） |
   | Build & Output Settings → Output Directory | **`docs`** |
   | Environment Variables | 无需配置 |

   > `vercel.json` 里已声明 `outputDirectory: "docs"` 与 `framework: null`，
   > 正常情况下 Vercel 会自动读取，表格中的值仅用于核对。

4. 点 **Deploy**，约 1–2 分钟后即可获得 `https://xiuxian-xxx.vercel.app`

之后每次 `git push` 到 `main` 分支，Vercel 会自动重新部署。

`vercel.json` 做了三件事：

- 指定输出目录为 `docs`
- 为 `.wasm` / `.pck` 设置一年强缓存（文件名带哈希时安全；本游戏文件名固定，
  若后续更新后遇到缓存问题，改一次文件名即可）
- 追加 `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` 响应头，
  与本地开发服务器保持一致；当前无线程构建并不需要它们，
  但保留可兼容日后切换到多线程构建

> 也可以用 CLI 部署：`npx vercel --prod`（首次会引导登录并绑定项目）。

### 绑定自定义子域名

部署完成后，在 Vercel 项目里绑定自己的域名即可。以 `xiuxian.449997.xyz` 为例：

1. Vercel 项目 → **Settings** → **Domains** → 输入 `xiuxian.449997.xyz` → **Add**
2. 若 Vercel 提示需要添加 DNS 记录，在域名 DNS 处添加：

   | 类型 | 名称 | 值 | TTL |
   |---|---|---|---|
   | CNAME | `xiuxian` | `cname.vercel-dns.com` | 自动 |

   > 若该域名的 NS 已托管给 Vercel（`ns1.vercel-dns.com` / `ns2.vercel-dns.com`），
   > Vercel 会自动写入这条记录，无需手动添加。

3. 等待 1–5 分钟，Vercel 自动签发 Let's Encrypt 证书，
   之后即可通过 `https://xiuxian.449997.xyz` 访问。

验证是否生效：

```bash
nslookup xiuxian.449997.xyz
curl -sI https://xiuxian.449997.xyz/ | head -3
```

> 若使用 GitHub Pages 托管，改为在仓库 `Settings → Pages → Custom domain` 填写域名，
> 并在 `docs/` 下放一个名为 `CNAME` 的文件（内容为域名），DNS 侧 CNAME 指向 `yemoren.github.io`。

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
├── vercel.json            # Vercel 部署配置
└── project.godot
```

## 技术栈

- **引擎**：Godot 4.7.2（GDScript）
- **渲染**：GL Compatibility（WebGL 友好）
- **导出目标**：Web / WebAssembly（无线程构建，因此**不依赖** COOP/COEP 响应头，
  可直接托管在 GitHub Pages 等静态平台上）
- **存档**：`user://` 持久化

## 版本

当前版本 **v1.1.3**，完整历史见 [CHANGELOG.md](CHANGELOG.md)。
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

| 版本 | 日期 | 说明 |
|---|---|---|
| [v1.1.3](https://github.com/yemoRen/xiuxian/releases/tag/v1.1.3) | 2026-09-18 | 逐出宗门、解除师徒、大比到点自动暂停、收徒/拜师限内门、聚灵阵实装与灵石月凝、选人弹窗卡死修复、通知条宣纸化 |
| [v1.1.2](https://github.com/yemoRen/xiuxian/releases/tag/v1.1.2) | 2026-09-18 | 门徒详情弹窗误触修复、宗门大比弹窗 UI 重做（步骤条 / 整卡选中 / 战报卡） |
| [v1.1.1](https://github.com/yemoRen/xiuxian/releases/tag/v1.1.1) | 2026-09-18 | 杂役效率改每人和 1%、大比弹窗点选修复、常驻悬浮「回到最新」 |
| [v1.1.0](https://github.com/yemoRen/xiuxian/releases/tag/v1.1.0) | 2026-09-18 | 更名「我的掌上仙宗」、生产体系（品阶选择/基准工时）与宗门大比重做 |
| [v1.0.10](https://github.com/yemoRen/xiuxian/releases/tag/v1.0.10) | 2026-09-17 | 功法强度与撰写人造诣挂钩、堕魔节奏放缓、死亡类功法取负、新增 50 条行动事件、寒潭灵脉 +10% |
| [v1.0.9](https://github.com/yemoRen/xiuxian/releases/tag/v1.0.9) | 2026-09-16 | 三道天劫（九天雷劫 / 破妄灵劫 / 飞升玄劫）、重生三层替死、修炼曲线与寿元重平衡、冲关失败掉一成进度、洗孽池 50 级上限 |
| [v1.0.8](https://github.com/yemoRen/xiuxian/releases/tag/v1.0.8) | 2026-09-16 | 全出血布局、门徒名册筛选排序与详情页鎏金、顶栏渐隐融合、状态栏真读、特质五类着色 |
| [v1.0.7](https://github.com/yemoRen/xiuxian/releases/tag/v1.0.7) | 2026-09-16 | 建立宗门三步向导、灵根品质四颗示意图、灵根属性细分、自绘鎏金效率条 |
| [v1.0.6](https://github.com/yemoRen/xiuxian/releases/tag/v1.0.6) | 2026-09-15 | 行动页「宗门编年」时间轴、正文语义着色、全屏手指滑动、经历页显示区域放大 |
| [v1.0.5](https://github.com/yemoRen/xiuxian/releases/tag/v1.0.5) | 2026-09-15 | 触摸手势闸门、滚动不再回弹、可滑动范围指示、陀螺仪滚轮、灵根分组规则 |
| [v1.0.3](https://github.com/yemoRen/xiuxian/releases/tag/v1.0.3) | 2026-09-15 | 思源宋体 / 黑体接入、图标素材体系（30 枚）、包体瘦身 |
| [v1.0.2](https://github.com/yemoRen/xiuxian/releases/tag/v1.0.2) | 2026-09-14 | 移动端适配：输入兜底、手指拖动滚动、字号与 UI 放大 |
| [v1.0.1](https://github.com/yemoRen/xiuxian/releases/tag/v1.0.1) | 2026-09-14 | 战斗损耗系统、经历着色、武力当前/最大显示、还春丹治伤势 |
| [v1.0.0](https://github.com/yemoRen/xiuxian/releases/tag/v1.0.0) | 2026-09-14 | 首个公开版本，Web 版发布 |

## 关于原创与参考

**玩法参考**：本作的门派经营玩法框架参考（致敬）了手机游戏《论如何建立一个修仙门派》，
在此之上进行了大量原创拓展与重新设计。

**原创拓展**（部分）：

- **七峰职务与加权效率模型** —— 峰主 100% / 副手 50% / 外门 20% / 杂役每人 +1%，
  并区分"探索型"与"生产型"峰的效率属性
- **杂役弟子编制管理** —— 独立人口池、按旬分配、全宗 300 / 单峰 100 双层上限
- **产出门槛判定** —— 四座资源峰未达人员门槛时零产出，杜绝"空峰白嫖"
- **事件物品品阶匹配** —— 弟子奇遇获得/失去的丹药、灵草、灵矿品阶与其境界挂钩，
  不会出现"筑基弟子获得仙阶至宝"这类错位
- **功德建筑体系** —— 12 座建筑跨轮回永久保留，构成长线成长曲线
- **事件体系扩展** —— 事件扩充至 50+ 条，含 A/B 双分支与归因追踪
- **法宝装备与秘境探索** —— 五槽位 / 十品阶装备，搭配寻幽峰秘境探索玩法

**美术**：本作**未使用、也未参考**原作的任何美术素材。
游戏内全部界面与图形均由 GDScript 程序化绘制（Canvas 矢量），
项目中不存在任何图片素材；唯一使用的外部资源是开源像素字体
[Fusion Pixel](https://github.com/TakWolf/fusion-pixel-font)（SIL Open Font License 1.1）。

**代码**：全部为独立编写的 GDScript，未使用原作任何代码或数据文件。

如原作者或相关权利人认为本项目有不妥之处，请通过
[Issues](https://github.com/yemoRen/xiuxian/issues) 联系，我会第一时间处理。

---

用 Godot 4 制作 · 个人学习项目
