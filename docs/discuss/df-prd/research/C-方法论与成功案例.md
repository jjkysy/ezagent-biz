# C · 方法论与成功案例

> 研究目的：为"在 ezagent 上搭一个团队产品开发 workspace"找一套**战略 → 产品 → 开发 → 运营 → ROI → 再循环**的可落地方法论，并用**真实公司案例**佐证。
> 全程大白话。引用 ezagent 代码/文档带 file 路径；引用外部材料带可核查链接。
>
> 一句话结论：这套需求（一张思维导图把"定位→痛点→体验→功能→开发→运营"串起来，每个节点有人认领、产物挂载，每人一个 agent，一个网页出口）在业界**不是新发明**——它是把几个成熟方法论（Amazon 工作回溯、Shape Up、持续探索、北极星指标、Lean 循环）缝在一起，再用 ezagent 的能力（每人一个 agent、external_mirror 出站、socialware 网页出口、编排器动态生成界面）做"活的载体"。下面先讲方法论怎么串，再讲怎么映射到 ezagent，最后给 6 个真实案例。

---

## 0 · 先把"思维导图"这件事说清楚

用户的核心诉求是**一张思维导图当中枢**：从产品定位一路串到营销运营，每个节点逻辑相连、有的放矢，节点有人认领、产物挂载。

业界没有一个叫"产品思维导图方法论"的东西，但有三套**树状/分层**的成熟做法，正好能填满这张图的不同层：

| 思维导图的层 | 对应的成熟方法 | 它解决"这一层填什么" |
|---|---|---|
| 根：**为什么做 / 给谁 / 定位** | Amazon 工作回溯（Working Backwards）的 **PR/FAQ** | 先写"假新闻稿"——产品上线那天对客户怎么说，逼你从客户体验倒推 |
| 中：**解决什么痛点 → 机会** | Teresa Torres **机会-方案树**（Opportunity Solution Tree） | 把"想达成的结果"挂在根，下面挂"客户痛点（机会）"，再下面才挂"方案" |
| 中下：**功能 / 方案 → 排序** | **RICE / ICE** 打分 | 同一个痛点下好几个方案，用分数决定先做哪个 |
| 叶：**具体开发（每天一小块）** | Shape Up 的 **pitch + 6 周周期** / Linear 的 **2 周 cycle + issue** | 把方案切成有边界、能在固定时间盒里做完的小块 |
| 贯穿：**衡量（ROI/北极星）** | **North Star Metric + 输入指标** | 每个功能点连到"它拨动哪个输入指标 → 进而抬北极星" |
| 循环：**学到了什么 → 回填根** | Lean Startup **Build-Measure-Learn** | 做完测完，把学到的东西回填到机会树，再循环 |

**关键洞察**：机会-方案树（OST）本身就是一棵树，天然是"思维导图"。它的结构是 `结果(根) → 机会(客户痛点) → 方案 → 实验`，正好就是用户要的"定位→痛点→功能→开发"的中段骨架。我们这张产品思维导图，本质就是**把 OST 往上接 PR/FAQ（定位层）、往下接 Shape Up/cycle（开发层）、横向挂北极星指标（衡量层）**。
参考：[Teresa Torres 机会-方案树原文](https://www.producttalk.org/opportunity-solution-trees/)。

---

## 1 · 战略 → 产品：单页/思维导图驱动的几种方法

### 1.1 Amazon 工作回溯 + PR/FAQ（定位层怎么填）

做法：动手写代码之前，先写一份**未来的新闻稿（PR）**——假装产品已经上线，对客户宣布它。再配一份 **FAQ**（5 页内），把"客户体验细节 + 我们要付出多大代价"都写清楚。逼团队从**客户体验倒着推**，而不是从"我们能做什么"正着想。Amazon 一个产品常写十几版 PR/FAQ、跟 leadership 来回五次以上才定稿。

为什么对我们有用：思维导图的**根节点**就应该是一份 PR/FAQ。它定义了"我们在给谁解决什么、上线那天怎么说"。这是整张图"有的放矢"的源头。
参考：[Working Backwards PR/FAQ 流程](https://workingbackwards.com/concepts/working-backwards-pr-faq-process/)、[模板](https://workingbackwards.com/resources/working-backwards-pr-faq/)。

### 1.2 北极星指标 + 输入指标（衡量层怎么填）

做法：选**一个**最能代表"产品给客户的核心价值"的指标当北极星（North Star Metric，Sean Ellis 提出）。北极星是**结果**，下面挂 3-5 个**输入指标**（团队真正能拨动的杠杆）。Amplitude 的说法：北极星是输出，输入指标是杠杆，团队的活就是"按对顺序拉对杠杆"。好的北极星是**领先指标**（预测未来）、能被团队影响、人话能讲清、不是虚荣指标。

为什么对我们有用：这是把"功能点"和"ROI"挂钩的桥。每个功能节点都要能回答"我拨动哪个输入指标"。见第 3 节。
参考：[Amplitude North Star Playbook](https://amplitude.com/books/north-star/about-north-star-framework)、[为什么用北极星框架](https://amplitude.com/books/north-star/why-use-the-north-star-framework)。

### 1.3 持续探索 + 机会-方案树（痛点层怎么填）

做法（Teresa Torres）：探索不是项目开头做一次，而是**每周的节奏**——每周跟客户聊，从访谈里收集**真实痛点**（机会），而不是直接收集方案。把一个想达成的**结果**放树根，下面挂从访谈里听到的**机会（痛点）**，再下面挂**方案**，最下面挂**假设实验**。诀窍：把方案拆成"底层假设"，多数假设一两天就能测，而整个想法要测好几周。

为什么对我们有用：这棵树就是思维导图的中段主干，而且它**强制每个方案都挂在一个真实客户痛点下**——天然防止"为做而做"。
参考：[机会-方案树](https://www.producttalk.org/opportunity-solution-trees/)、[Continuous Discovery Habits 书摘](https://andrewclark.co.uk/product-book-summaries/continuous-discovery-habits)。

### 1.4 RICE / ICE 优先级（同一痛点下，先做哪个方案）

- **RICE**（Intercom 产品团队提出）：`分数 = (Reach 触达 × Impact 影响 × Confidence 信心) / Effort 成本`。适合有用户数据的成熟团队。
- **ICE**（Sean Ellis 为 Dropbox/LogMeIn 的增长实验提出）：`分数 = Impact 影响 × Confidence 信心 × Ease 容易度`，1-10 打分，更快更糙，适合早期和增长实验。

为什么对我们有用：思维导图里同一个痛点节点下会冒出好几个方案子节点，给每个子节点标一个 ICE/RICE 分，排序就有了依据，不靠拍脑袋。
参考：[RICE（Intercom 出处）vs ICE 对比](https://www.productlift.dev/blog/rice-vs-ice/)、[ICE 原始框架](https://growthmethod.com/ice-framework/)。

### 1.5 Shape Up（叶节点怎么切成能做完的开发块）

做法（Basecamp，2019）：
- **塑形（Shaping）**：把粗想法打磨成有边界的方案，写成一页 **pitch**（说清楚：问题、约束、方案、坑、不做什么）。
- **下注（Betting）**：每个周期前开"下注会"，从 pitch 里挑几个**押注**进下个周期，而不是维护一个无限长 backlog（"Bets, not Backlogs"）。
- **6 周周期 + 2 周冷却**：6 周是"能做出有意义的东西"的最优时间盒。
- **断路器（Circuit Breaker）**：押注的时间盒到了没做完，**默认不延期**，项目回炉重塑。

为什么对我们有用：这是把思维导图叶子（一个方案）变成"团队能在固定时间盒里交付"的纪律。pitch ≈ 挂在叶节点上的一页 spec；下注 ≈ 每周选节点开工。
参考：[Shape Up 全书](https://basecamp.com/shapeup)、[下注会](https://basecamp.com/shapeup/2.3-chapter-09)、[Bets, Not Backlogs](https://basecamp.com/shapeup/2.1-chapter-07)。

### 1.6 Lean Startup（让整张图转起来的循环）

做法（Eric Ries）：**Build → Measure → Learn** 循环，进步的单位是"**验证后的学习**"。用 **MVP**（最小可行产品）以最小成本最快跑完一圈循环，验证一个关键假设。

为什么对我们有用：这是思维导图"再循环"的发动机——做完一个功能（Build）、看指标（Measure）、把学到的回填机会树（Learn），再选下一个节点。
参考：[Lean Startup 原则](https://theleanstartup.com/principles)。

### 1.7 产品驱动增长 PLG（运营层的底层心智）

做法（OpenView，Blake Bartlett 2016 提出）：让**产品本身**当获客/留存/扩张的主引擎——自助上手、靠产品体验把用户带到"啊哈时刻"，用**产品合格线索（PQL）**（看用户在产品里的真实行为，而不是市场/销售打的标）判断谁该被销售跟进。

为什么对我们有用：运营节点不该只是"发推/投广告"，而该是"设计产品里的自助路径和啊哈时刻"。dogfooding 自己用自己的产品，正是 PLG 的天然实践场。
参考：[OpenView PLG 定义](https://openviewpartners.com/product-led-growth/)、[用 PQL 做 PLG 的 5 根支柱](https://openviewpartners.com/blog/the-5-pillars-for-product-led-growth-using-product-qualified-leads)。

---

## 2 · dogfooding 迭代节奏怎么落地

用户要的节奏：**每天完成一个小功能点 / 每周 1-2 个用户价值闭环 / 每周 1 轮运营策略调整与执行**。这正好能用业界三套真实节奏拼出来：

### 2.1 节奏骨架（三层时间盒）

| 周期 | 干什么 | 借鉴的真实做法 |
|---|---|---|
| **每天** | 完成思维导图上**一个叶节点**（一个小功能点 / 一份 spec），产物挂回节点 | Linear 的"issue 切到能几天做完、每天有可见进展"；Lean 的"最快跑完一圈" |
| **每周** | 交付 **1-2 个用户价值闭环**（一个能被用户感知到的完整小价值）；同时跑 **1 轮探索**（跟客户/dogfood 用户聊）+ **1 轮运营调整** | Teresa Torres"每周持续探索"；Linear"每周 changelog 逼着持续 ship"；轮值 goalie 处理反馈 |
| **每 4-6 周** | 一个"押注"做完，回看北极星动没动，重塑机会树 | Shape Up"6 周周期 + 2 周冷却 + 下注会" |

### 2.2 每天的小功能点：用 Linear 的"切到能完成"原则

Linear 的方法：把工作拆成**几天就能做完**的 issue，每周理想能完成好几个具体任务，让进展**可见**。配 feature-flag，新功能尽快推到内部试用——"没有理由等着才 ship"。
参考：[Linear Method](https://linear.app/method/introduction)、[Lenny: How Linear builds product](https://www.lennysnewsletter.com/p/how-linear-builds-product)。

### 2.3 每周的用户价值闭环：用 Linear 的 changelog 当"逼自己交付"的钟摆

Linear **每周发 changelog**，哪怕很小也发——这个纪律本身**逼团队每周都 ship 出能讲给用户的东西**，并形成"庆祝进展"的文化动量。这正好对应用户要的"每周 1-2 个用户价值闭环"：闭环的标志 = 这周 changelog 能写出一条用户能感知的价值。
参考：[Linear 如何用公开 changelog 驱动增长与文化](https://lastrelease.io/blog/how-linear-uses-a-public-changelog)、[Linear changelog](https://linear.app/changelog)。

### 2.4 每周的运营调整：用 Superhuman 的 PMF 引擎当"每周一测"的仪表

Superhuman 把 PMF 当**永久的每周练习**：每周测一次 PMF 分（"如果不能再用这个产品你会多失望？"答"非常失望"的占比，>40% 是 magic 线），月度/季度汇总，一半路线图加固铁粉爱的点、一半消除墙头草的顾虑——一年把分数从 22% 拉到 58%。这给"每周 1 轮运营策略调整"提供了一个**可量化的方向盘**：每周看分 → 决定这周加固还是补短。
参考：[First Round: Superhuman 的 PMF 引擎](https://review.firstround.com/how-superhuman-built-an-engine-to-find-product-market-fit/)。

### 2.5 dogfooding 本身：用 Notion / Figma 的"自己天天用自己"

- **Notion** 整个公司用 Notion 跑自己（知识库、项目计划、会议纪要全在 Notion），员工整天泡在只给员工的测试环境 **Notion Dev** 里实时试新功能——形成"用自己产品 → 发现痛点 → 做更好的产品"的良性循环。
- **Figma** 办 **Maker Week**（全员黑客周，不只产品团队）和全员竞赛，把 dogfooding 做成文化，降低"动手试错"的门槛。

这正是我们这个 workspace 的本质：**团队在 ezagent 上搭 workspace，又用这个 workspace 来开发 ezagent 主产品线**——自己吃自己的狗粮。
参考：[Notion 如何用 Notion](https://ones.com/blog/knowledge/how-notion-uses-notion-revolutionize-workflow/)、[Inside Notion](https://colossus.com/article/inside-notion/)、[Figma 把 dogfooding 做成文化（OpenAI 案例）](https://openai.com/index/figma-david-kossnick/)。

---

## 3 · ROI / 北极星指标体系怎么和功能点挂钩

目标：思维导图上**每个功能节点**都能回答"我为什么值得做"，并且能事后验证。

### 3.1 三层挂钩（北极星 → 输入指标 → 功能点）

```
北极星指标（结果，1 个）            例：每周完成的"用户价值闭环"数
  ├─ 输入指标 A（杠杆）             例：思维导图节点的"认领率"
  ├─ 输入指标 B（杠杆）             例：节点从认领到产物挂载的周期
  └─ 输入指标 C（杠杆）             例：每周探索访谈条数
        └─ 功能点（叶节点）         每个功能点 = 拨动某个输入指标的一次尝试
```

Amplitude 的口径：北极星是输出，输入指标是杠杆，活儿就是按对顺序拉对杠杆（[出处](https://amplitude.com/books/north-star/about-north-star-framework)）。

### 3.2 给每个功能节点贴的"挂钩牌"（建议字段）

| 字段 | 含义 | 取自 |
|---|---|---|
| **挂在哪个痛点下** | 这个功能解决机会树上哪个客户痛点 | OST |
| **拨动哪个输入指标** | 做完它，哪个输入指标会动、动多少（假设） | North Star |
| **RICE/ICE 分** | 触达×影响×信心 / 成本（或 影响×信心×容易） | RICE/ICE |
| **验证假设** | 这个功能赌的是哪条假设，怎么最快测 | Lean / Torres |
| **闭环判据** | 怎么算"这个功能的用户价值闭环达成" | Lean / Linear changelog |

这张牌一贴，"ROI 和功能点挂钩"就从口号变成**每个节点都能查的数据**。事后回看输入指标动没动，就是 Build-Measure-Learn 的 Measure/Learn。

---

## 4 · 6 个真实公司案例（战略 → 开发 → 运营如何串成闭环）

> 每个案例标注：用什么把战略接到开发、什么节奏、什么工具、可核查链接。

### 案例 1 · Linear —— 用自己的产品 + 每周 changelog 把"战略→开发→运营"焊死

- **闭环**：Roadmap → Projects → **Cycles（2 周）** → Issues；客户的 bug/需求直接进 **Triage**（团队收件箱），每周轮值的 "goalie" 工程师分流。**用 Linear 开发 Linear**（自己吃狗粮）。
- **节奏**：2 周 cycle 是软件团队最常见时长；issue 切到几天能完成；feature-flag 让新功能尽快内测——"没有理由等着才 ship"。
- **运营接口**：**每周发 changelog**，哪怕很小也发，逼着持续交付 + 形成文化动量。
- **工具**：Linear 自己。
- 链接：[Linear Method](https://linear.app/method/introduction)、[2 周 cycle 指南](https://workmanagementhub.com/linear-cycles-sprint-planning-guide-2026/)、[Lenny: How Linear builds product](https://www.lennysnewsletter.com/p/how-linear-builds-product)、[公开 changelog 驱动增长](https://lastrelease.io/blog/how-linear-uses-a-public-changelog)。
- **对我们最直接的样板**：cycle + Triage + changelog 这三件套，几乎就是用户要的"每天小功能 / 每周闭环 / 每周运营"的现成模板。

### 案例 2 · Superhuman —— 把"找 PMF"变成可量化、每周一测的引擎

- **闭环**：四问卷（不能用了会多失望/谁最受益/最大收益是什么）→ 按"最高期待客户"分群 → 分析爱与抗拒的原因 → 路线图一半加固一半消除顾虑 → 每周测分回到第一步。
- **节奏**：用户用满约 21 天发问卷；**每周**测 PMF 分，月度/季度汇总；一年把分数从 **22% → 58%**。
- **战略→开发挂钩**：PMF 分直接决定路线图分配（加固 vs 补短）——这就是"指标驱动功能优先级"的活样板。
- 链接：[First Round 原文](https://review.firstround.com/how-superhuman-built-an-engine-to-find-product-market-fit/)、[Coda 版引擎](https://coda.io/@rahulvohra/superhuman-product-market-fit-engine)。
- **对我们最直接的样板**：第 2.4 / 3 节的"每周一测的方向盘"。

### 案例 3 · Notion —— 极致 dogfooding，用自己跑自己

- **闭环**：知识库、项目计划、会议纪要、功能 backlog、bug、用户反馈**全在 Notion 里**；员工泡在 **Notion Dev** 测试环境里实时试半成品 AI 功能。
- **节奏/文化**：原型 → dogfood → 反馈的循环是日常驱动力；精简团队靠"自己用自己的工具"保持敏捷协调，不靠重管理层级。
- **工具**：Notion 自己 + 自建数据库给反馈分类排序。
- 链接：[How Notion uses Notion](https://ones.com/blog/knowledge/how-notion-uses-notion-revolutionize-workflow/)、[Inside Notion](https://colossus.com/article/inside-notion/)、[docs-first 团队 wiki 指南](https://www.notion.com/help/guides/build-a-docs-first-culture-with-a-beautiful-team-wiki-powered-by-a-database)。
- **对我们最直接的样板**："文档+数据库当中枢、团队天天住在里面"——正是 obsidian/feishu + 数据库 + 思维导图的目标形态。

### 案例 4 · Figma —— 把 dogfooding 和试错做成全员文化

- **闭环**：设计系统集中化（组件/字体共享）→ 每次探索都从系统出发 → 一致性默认发生；**Maker Week**（全员黑客周）和全员竞赛把"动手试新东西"的门槛压到最低。
- **节奏**：周级黑客周 + 跨时区 live jam，让非技术岗也敢上手。
- 链接：[Figma dogfooding 文化（OpenAI 案例）](https://openai.com/index/figma-david-kossnick/)、[设计系统入门](https://help.figma.com/hc/en-us/articles/14552802134807-Lesson-1-Welcome-to-design-systems)。
- **对我们最直接的样板**：思维导图节点"人人可认领、人人挂产物"——降低参与门槛、让非核心岗也产出，就是 Maker Week 精神。

### 案例 5 · Stripe —— 把"质量门 + 工作回溯"嵌进开发流程

- **闭环**：深度理解用户、从用户**倒推**；用 **shaping**（在大战略和详细 PRD 之间，先做粗方案填空）；开发团队花 **exposure hours** 直接跟开发者待在一起看他们怎么集成；任何改 API 的变更必须过 **API Review**（跨职能小组的强制评审，常传阅 20 页设计文档）。
- **战略→开发挂钩**：把"API 质量"当**面向用户的功能**来做（幂等、版本、显式失败模式），质量门是流程里的强制环节，不是事后补。
- 链接：[Stripe 产品策略案例](https://www.uladshauchenka.com/p/product-at-stripe-a-case-study-in)、[Building Products at Stripe（Ken Norton）](https://www.bringthedonuts.com/essays/building-products-at-stripe/)、[How Stripe Builds APIs（Postman）](https://blog.postman.com/how-stripe-builds-apis/)。
- **对我们最直接的样板**："每天产 spec"应有一个**质量门**（评审/exposure），别让 spec 注水；shaping ≈ 给叶节点写 pitch。

### 案例 6 · Basecamp（Shape Up）—— 时间盒 + 下注 + 断路器的纪律

- **闭环**：塑形写 pitch → 下注会挑押注 → **6 周周期** 做 → **2 周冷却** → 断路器（到点没做完默认不延期，回炉重塑）。
- **战略→开发挂钩**："押注"代替"计划"，刻意把活塞进 6 周盒子，保证周期末有**有意义的成品**。
- 链接：[Shape Up 全书](https://basecamp.com/shapeup)、[下注会](https://basecamp.com/shapeup/2.3-chapter-09)、[一个团队从 Sprint 转 Shape Up 的实战](https://medium.com/adventures-in-consumer-technology/why-we-transitioned-from-sprints-to-basecamps-shape-up-f416114224e7)。
- **对我们最直接的样板**：第 2.1 节的"每 4-6 周一个押注 + 冷却"那一层。

> 补充背书（不单列）：**Amazon** 的 PR/FAQ（[出处](https://workingbackwards.com/concepts/working-backwards-pr-faq-process/)）给"思维导图根节点 = 一份新闻稿"提供权威范式；**Dropbox/Intercom** 分别是 ICE / RICE 的真实出处（[RICE 出处](https://www.productlift.dev/blog/rice-vs-ice/)）。

---

## 5 · 怎么把这套方法论落到 ezagent 上（机制映射）

> 这是把上面方法论接到具体技术底座的部分。ezagent 上"搭新东西"有两条路，**这个 workspace 主要走路 B（socialware app，纯配置+编排，不改 core）**，少数缺的底层能力才走路 A（写 plugin）。出处：`docs/discuss/intro/09-如何在ezagent上搭建新app.md:6-18`。

### 5.1 需求 → ezagent 能力 对照表

| 用户要的 | ezagent 现成机制 | 出处（带 file 路径） |
|---|---|---|
| **网页出口**：显示状态、帮团队对齐 | **socialware app** = 一个带 `public_view: true` 的 **会话模板**；匿名/团队成员打开 `/socialware/chat?session_uri=…` 就能看 | `.claude/skills/ezagent-socialware/SKILL.md:31-51`；`docs/discuss/intro/09-如何在ezagent上搭建新app.md:43-69` |
| **客户/团队看到的界面**：动态、随状态变 | 界面是会话的**编排器 agent** 一轮轮组合出来的 React + json-render，**不是手写页面** | `.claude/skills/ezagent-socialware/SKILL.md:53-63`；`docs/discuss/intro/09-...md:71-72` |
| **每个使用者一个自己的 agent**：追踪自己的活、能和别人对话 | `Entity.Agent` + **flavor**（cc / codex / curl 等口味），每人 spawn 一个自己 flavor 的 agent | `docs/discuss/intro/09-...md:30`（`agent_flavors/0`）、`:35-37`（抄现成 flavor）；`docs/discuss/intro/04-如何使用ezagent.md:43-45`（curl/cc 实测） |
| **产物挂载到节点 / 出到外部工具**（飞书、github） | **external_mirror**：出站把内容镜像到飞书/github 等外部；入站走 `InboundDispatcher → Invocation.dispatch` | `docs/discuss/intro/09-...md:36`（飞书出站=`ExternalMirror.Adapter`，入站=`InboundDispatcher`） |
| **加平台还没有的能力**（如新渠道/新 agent 类型） | 路 A：写一个 OTP plugin，`use Ezagent.Plugin`，只填声明回调，框架替你注册（编译期 `:ezagent_plugin_check` 强制） | `docs/discuss/intro/09-...md:22-39` |

### 5.2 把方法论的每一层映射到 ezagent

- **思维导图当中枢**：xmind/excalidraw 是**外部产物**，通过 external_mirror 双向挂到会话；思维导图每个节点对应一个会话状态项（认领人、产物链接、ICE 分、挂的输入指标）。节点产物（spec 在 obsidian/feishu、issue+PR 在 github、图在 excalidraw）都靠 external_mirror 出站镜像/入站回写。出处：`docs/discuss/intro/09-...md:36`。
- **每人一个 agent 追踪自己的活**：每个执行者 spawn 一个自己 flavor 的 `Entity.Agent`，它订阅"自己认领的节点"，并能跨 agent 对话（跨 Kind 唯一通路是 `Ezagent.Invocation.dispatch/1`，**不许** `PubSub.broadcast` 到入站 topic——P14 铁律）。出处：`docs/discuss/intro/09-...md:39`、`04-...md:38`。
- **网页出口 = 对齐面**：一个 socialware 会话当"团队状态出口"，编排器 agent 把"思维导图当前状态 + 各节点产物 + 北极星/输入指标"动态渲染成客户面。出处：`.claude/skills/ezagent-socialware/SKILL.md:53-72`。
- **产品方向落点**：在建的 **world**（统一前端，会退役并收编现在的 LiveView 管理面 + 客户面）和 **agent-schema**（编排契约）是这条产品线的未来落点；今天 `main` 上是 primitive 拼装、有粗糙边。**别假设 world/agent-schema 已存在**。出处：`.claude/skills/ezagent-socialware/SKILL.md:174-198`；`docs/discuss/intro/09-...md:104-109`。

### 5.3 落地时要当心的真坑（来自 socialware SKILL）

1. `public_view?/1` 读的是**活会话 slice**——会话没在服务节点里活着，匿名访客会被 302 弹去 `/login`。种会话必须和服务在**同一个 BEAM**。出处：`.claude/skills/ezagent-socialware/SKILL.md:126-138`。
2. `public_view` **没有 UI 开关**，只能内容/CLI 设；只有字面布尔 `true` 才开，`"true"`/缺失都按私有（fail-closed）。出处：`SKILL.md:66-90`。
3. 客户 SPA bundle 必须先 build（`pnpm install` + `mix assets.build`），否则页面 200 但空白。出处：`SKILL.md:143-147`。
4. 编排器 agent 重、要 cc 凭证、可能超时——**但会话仍会持久化**，断言断在会话上别断编排器。出处：`SKILL.md:110-117`；`docs/discuss/intro/09-...md:66`。
5. 工具链用 mise（OTP 27 / Elixir 1.18），命令加 `mise exec --` 前缀；服务端口 10042。出处：`docs/discuss/intro/04-如何使用ezagent.md:5`、`:100`。

---

## 6 · 一页总装图（思维导图怎么排）

```
[根] PR/FAQ：给谁解决什么 + 上线那天怎么说          ← Amazon 工作回溯
   │   北极星指标(1) + 输入指标(3-5)                ← Amplitude North Star
   │
[痛点层] 机会1   机会2   机会3 …                     ← Torres OST（每周访谈喂养）
   │        │
[方案层]   方案A[ICE 7.2]  方案B[ICE 5.1] …          ← RICE/ICE 排序
   │            │
[开发层]    pitch/spec（一页、有边界）                ← Shape Up shaping
   │            ├─ issue（几天做完，每天一个小功能点） ← Linear cycle
   │            └─ 产物挂载：spec/issue/PR/图          ← external_mirror 出站
   │
[衡量/循环] 做完→看输入指标动没动→回填机会树→再选节点  ← Lean Build-Measure-Learn
   │
[运营层] 每周 changelog（用户价值闭环）+ 每周 PMF 测分 ← Linear changelog + Superhuman 引擎

承载：每个节点有【认领人(一个 Entity.Agent flavor)】+【产物链接】+【挂钩牌(痛点/输入指标/ICE/假设/闭环判据)】
出口：一个 socialware 会话，编排器 agent 把整棵树+指标动态渲染成网页对齐面
```

节奏：**每天**填一个叶（小功能点）→ **每周**交 1-2 个用户价值闭环 + 1 轮探索访谈 + 1 轮运营调整（看 PMF 分）→ **每 4-6 周**结一个押注、回看北极星、重塑树。

---

## 参考链接汇总（可核查）

战略/产品方法：
- 工作回溯 PR/FAQ：https://workingbackwards.com/concepts/working-backwards-pr-faq-process/ ；模板 https://workingbackwards.com/resources/working-backwards-pr-faq/
- 北极星框架（Amplitude）：https://amplitude.com/books/north-star/about-north-star-framework ；https://amplitude.com/books/north-star/why-use-the-north-star-framework
- 机会-方案树（Teresa Torres）：https://www.producttalk.org/opportunity-solution-trees/ ；书摘 https://andrewclark.co.uk/product-book-summaries/continuous-discovery-habits
- RICE vs ICE：https://www.productlift.dev/blog/rice-vs-ice/ ；ICE 框架 https://growthmethod.com/ice-framework/
- Shape Up：https://basecamp.com/shapeup ；下注会 https://basecamp.com/shapeup/2.3-chapter-09 ；Bets not Backlogs https://basecamp.com/shapeup/2.1-chapter-07
- Lean Startup 原则：https://theleanstartup.com/principles
- PLG（OpenView）：https://openviewpartners.com/product-led-growth/ ；PQL 5 支柱 https://openviewpartners.com/blog/the-5-pillars-for-product-led-growth-using-product-qualified-leads

案例：
- Linear：https://linear.app/method/introduction ；https://www.lennysnewsletter.com/p/how-linear-builds-product ；https://lastrelease.io/blog/how-linear-uses-a-public-changelog ；2 周 cycle https://workmanagementhub.com/linear-cycles-sprint-planning-guide-2026/
- Superhuman：https://review.firstround.com/how-superhuman-built-an-engine-to-find-product-market-fit/ ；https://coda.io/@rahulvohra/superhuman-product-market-fit-engine
- Notion：https://ones.com/blog/knowledge/how-notion-uses-notion-revolutionize-workflow/ ；https://colossus.com/article/inside-notion/ ；https://www.notion.com/help/guides/build-a-docs-first-culture-with-a-beautiful-team-wiki-powered-by-a-database
- Figma：https://openai.com/index/figma-david-kossnick/ ；https://help.figma.com/hc/en-us/articles/14552802134807-Lesson-1-Welcome-to-design-systems
- Stripe：https://www.uladshauchenka.com/p/product-at-stripe-a-case-study-in ；https://www.bringthedonuts.com/essays/building-products-at-stripe/ ；https://blog.postman.com/how-stripe-builds-apis/
- Basecamp/Shape Up 实战：https://medium.com/adventures-in-consumer-technology/why-we-transitioned-from-sprints-to-basecamps-shape-up-f416114224e7

ezagent 内部（file 路径）：
- `.claude/skills/ezagent-socialware/SKILL.md`（socialware = public_view 会话模板、编排器生成界面、落地真坑）
- `docs/discuss/intro/09-如何在ezagent上搭建新app.md`（路 A plugin / 路 B socialware、agent flavor、external_mirror）
- `docs/discuss/intro/04-如何使用ezagent.md`（e2e 走查、agent flavor 实测、工具链/端口）
