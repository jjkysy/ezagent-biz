# Bootstrap 基线说明 — e2abc02f (2026-06-21)

本 worktree(ezagent-web-prd-master)已重置到上游最新 main `e2abc02f`。
相对上一次 bootstrap(44db7a17)新增 13 个提交，**结构无大变(仍 21 app)**：
- anon-user epic(#68)：匿名外部用户接管/合并/relabel(post-auth takeover、merge member claim repair、session-scope messages)。直接服务客户面产品线。
- **新增 `.claude/skills/ezagent-socialware` 编写 skill(#877)**：socialware 作者流程权威文档。

## 测试基线
工具链 = mise OTP27/1.18(`mise exec -- mix test`)。结构同上次：14/19 类全绿，liveview 一批确定性失败(前端版本兼容/测试基础设施,非产品坏;实测 new-agent/invite 按钮坏)。**本仓库无 CI**,主线可能带红。

## 真实 agent 验证(本会话实测,见 docs/discuss/intro/04)
- echo ✅ / curl-deepseek ✅("PONG") / cc-claude ✅("PONG",修了 2 个 claude 2.1.185 对话框兼容 bug,commit 0cc522cb)

## 产物
- docs/discuss/intro/ 00-04 + 08 + 09(含 socialware 深入 + 如何搭新 app,产品设计视角)。
- 本分支定位:产品设计 + 工作流,不是修 bug/底层开发。
