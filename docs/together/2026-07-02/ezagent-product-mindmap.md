# ezagent：可灵活组合 app 的组织操作系统

> 树 = 推导链：定位主张 → 指标 → 功能 → 开发。每个节点一个父级，stage 是深度不是分组。
> 颜色/标注 = 这个点由谁 cover：〔基座〕〔world〕〔官网〕〔kanban〕〔autoservice〕〔hello〕

## 基本操作单元是对话 〔world〕

### 指标：组织日常操作全部在对话内完成
- 功能：World 统一操作台（IM 三栏）〔world〕
  - 开发：world 向 IM 收敛（#1118 T3）
- 功能：一切操作是消息 + 能力券门控 〔基座〕
  - 开发：已就位（dispatch + CapBAC 原语）

## 对话中可快速搭建 agent 〔world〕

### 指标：一句话到 agent 进场干活
- 功能：recipe × flavor 一句话物化 〔基座〕
  - 开发：B#1116 物化基座（在途）
  - 开发：C#1115 配方归属决策（在途）
- 功能：agent 间接力（会话层 routing）〔基座〕
  - 开发：app 的 routing 声明字段（待建）

## 组织具备自己的工作空间 〔基座〕

- 功能：workspace 租户隔离 + 成员管理
  - 开发：已就位

## 对话可快速转型成 app 〔基座〕

### 指标：一句话到可用 app 的时间
- 功能：会话装上 app 即成运行沙盒 〔基座〕
  - 开发：泛化 installs 装配契约
- 功能：一键发布（公开地址 + 身份寻址）〔基座〕
  - 开发：统一发布接口
  - 开发：官网本周上线（#1121 已并 + #1118 + 绑域名）〔官网〕

## app 可拆分 / 组合 〔基座〕

### 指标：app 被复用 / 组合进新 app 的次数
- 功能：一个会话装多个 app 〔基座〕
  - 开发：app package 统一声明（#1125 + gaga T7）
  - 开发：统一声明抽象（收敛五处复制）
- 功能：组合打包成新 app 〔基座〕
  - 开发：嵌套 vs 扁平（待 Allen 拍板）
  - 开发：官网当嵌套 conformance 样例 〔官网〕

## 对话中的 element 可被寻址 〔基座〕

- 功能：entity / session / config URI
  - 开发：app 的寻址方案（待拍板）

## 解决组织运转效率与信息损耗（吃自己狗粮验证）

### 指标：团队开发流闭环流转 〔kanban〕
- 功能：九阶段链 + pm 派活 + dev 接力 + github 同步
  - 开发：D/E held · 扁平 conformance 样例

### 指标：客服流程端到端跑通 〔autoservice〕
- 功能：匿名进线 + KB 检索 + persona
  - 开发：KB 外化（#1120）· seed 重表达为 app

### 指标：一句话出可发布页面 〔hello〕
- 功能：AI 生成页 + Surface 版本门 + 匿名交付
  - 开发：substrate 已上线 · 被官网复用
