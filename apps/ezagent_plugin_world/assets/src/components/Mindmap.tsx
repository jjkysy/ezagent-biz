import {useEffect, useState} from "react"
import {ExternalLink, Hand, Paperclip, Pencil, Plus, RefreshCw, Send, Target, Trash2} from "lucide-react"

import {Button} from "./ui/primitives"
import {MindmapCanvas, STAGE_LABEL, STAGES} from "./MindmapCanvas"

const STATUS_ICON: Record<string, string> = {unassigned: "○", claimed: "◔", doing: "◑", done: "●"}

type Node = {
  parent_id: string | null
  title: string
  order: number
  stage: string | null
  owner: string | null
  status: string | null
  artifacts?: Record<string, unknown>[]
  metrics?: Record<string, unknown>[]
}

type Tree = {nodes: Record<string, Node>; root_id: string | null}

export type MindmapState = {
  component?: string
  mindmap_uri?: string | null
  instances?: {uri: string; name: string; path: string}[]
  tree?: Tree | null
  stages?: string[]
  statuses?: string[]
  miro_board_url?: string | null
  miro?: {configured?: boolean; board_id?: string | null}
  last_dispatch_status?: string | null
}

type Act = (action: string, args: Record<string, unknown>) => void

const inputCls =
  "rounded-md border border-border bg-background px-2.5 py-1.5 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-ring"

export function Mindmap({
  state,
  onAction = () => undefined,
  onShare,
}: {
  state: MindmapState
  onAction?: Act
  onShare?: () => void
}) {
  return state.mindmap_uri ? (
    <MindmapDetail state={state} onAction={onAction} onShare={onShare} />
  ) : (
    <MindmapList state={state} onAction={onAction} />
  )
}

// 插件配置页 = 只配 Miro 凭证（不在这编辑导图——编辑在会话内 Mindmap 子视图）。
function MindmapList({state, onAction}: {state: MindmapState; onAction: Act}) {
  const [token, setToken] = useState("")
  const configured = state.miro?.configured
  return (
    <div className="flex max-w-2xl flex-col gap-4 p-6">
      <div>
        <h2 className="text-lg font-semibold text-foreground">思维导图 · 配置</h2>
        <p className="text-sm text-muted-foreground">配置 Miro 镜像凭证。<strong>建树/认领/编辑在会话(session)里的 Mindmap 子视图</strong>，本页只配置。</p>
      </div>
      <div className="flex flex-col gap-3 rounded-md border border-border bg-card p-4">
        <div className="flex items-center gap-2">
          <span className="font-medium text-foreground">Miro 凭证</span>
          {configured ? (
            <span className="rounded bg-muted px-1.5 py-0.5 text-xs text-green-600 dark:text-green-400">已配置 ✓</span>
          ) : (
            <span className="rounded bg-muted px-1.5 py-0.5 text-xs text-muted-foreground">未配置</span>
          )}
        </div>
        <label className="flex flex-col gap-1 text-xs text-muted-foreground">
          Access Token
          <input type="password" className={`${inputCls} w-full`} placeholder="粘贴 Miro access token" value={token} onChange={(e) => setToken(e.target.value)} />
        </label>
        <div>
          <Button type="button" size="sm" onClick={() => token.trim() && onAction("mindmap.save_miro_creds", {access_token: token.trim()})}>
            保存凭证
          </Button>
        </div>
        <p className="text-xs text-muted-foreground">凭证存到 system://credentials/miro.yaml（节点级，0600，仅 admin 可改）。board 在同步时自动建/绑定，不用配。不配凭证也能用，只是会话内不同步。</p>
      </div>
      <Status state={state} />
    </div>
  )
}

function MindmapDetail({state, onAction, onShare}: {state: MindmapState; onAction: Act; onShare?: () => void}) {
  const uri = state.mindmap_uri as string
  const tree = state.tree || {nodes: {}, root_id: null}
  const stages = state.stages || STAGES
  const statuses = state.statuses || ["claimed", "doing", "done"]
  const instances = state.instances || []
  const [rootTitle, setRootTitle] = useState("")
  const [newName, setNewName] = useState("")
  const [selectedId, setSelectedId] = useState<string | null>(tree.root_id)

  // 切 board / 树变化后，选中节点若已不存在则回退到根
  useEffect(() => {
    if (selectedId && !tree.nodes[selectedId]) setSelectedId(tree.root_id)
  }, [tree, selectedId])

  const sel = selectedId ? tree.nodes[selectedId] : null
  const nodeArgs = selectedId ? {mindmap_uri: uri, id: selectedId} : {}

  return (
    <div className="flex h-full flex-col gap-3 p-5">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold text-foreground">思维导图 · {uri.split("/").pop()}</h2>
        <div className="flex items-center gap-2">
          {onShare && (
            <Button type="button" size="sm" variant="secondary" onClick={onShare}>
              <Send className="h-4 w-4" /> 分享到对话
            </Button>
          )}
          <Button type="button" size="sm" variant="secondary" onClick={() => onAction("mindmap.sync_miro", {mindmap_uri: uri})}>
            <RefreshCw className="h-4 w-4" /> 同步到 Miro
          </Button>
        </div>
      </div>
      {state.miro_board_url && (
        <a className="inline-flex items-center gap-1 text-sm text-primary hover:underline" href={state.miro_board_url} target="_blank" rel="noreferrer">
          <ExternalLink className="h-3.5 w-3.5" /> 打开 Miro 看板
        </a>
      )}

      <div className="flex flex-1 gap-3 overflow-hidden">
        {/* 侧边栏：导图列表 + 新建 + 选中节点属性 */}
        <aside className="flex w-64 flex-shrink-0 flex-col gap-3 overflow-y-auto">
          <div className="rounded-md border border-border p-2">
            <div className="mb-1.5 text-xs font-semibold text-muted-foreground">导图</div>
            <ul className="flex flex-col gap-0.5">
              {instances.map((i) => (
                <li key={i.uri}>
                  <button
                    type="button"
                    onClick={() => onAction("mindmap.select_board", {mindmap_uri: i.uri})}
                    className={`w-full truncate rounded px-2 py-1 text-left text-sm ${i.uri === state.mindmap_uri ? "bg-accent font-medium text-foreground" : "text-muted-foreground hover:bg-muted"}`}
                  >
                    {i.name}
                  </button>
                </li>
              ))}
            </ul>
            <div className="mt-2 flex gap-1">
              <input className={`${inputCls} w-full`} placeholder="新导图名" value={newName} onChange={(e) => setNewName(e.target.value)} />
              <Button type="button" size="sm" onClick={() => newName.trim() && (onAction("mindmap.create", {name: newName.trim()}), setNewName(""))}>
                <Plus className="h-4 w-4" />
              </Button>
            </div>
          </div>

          <div className="rounded-md border border-border p-2">
            <div className="mb-1.5 text-xs font-semibold text-muted-foreground">节点属性</div>
            {sel ? (
              <NodePanel node={sel} args={nodeArgs} stages={stages} statuses={statuses} onAction={onAction} />
            ) : (
              <p className="text-xs text-muted-foreground">点画布里的节点查看/编辑属性。</p>
            )}
          </div>
        </aside>

        {/* 画布 */}
        <div className="flex-1 overflow-hidden rounded-md border border-border">
          {!tree.root_id ? (
            <div className="flex gap-2 p-4">
              <input className={`${inputCls} w-72`} placeholder="根节点标题（产品发心）" value={rootTitle} onChange={(e) => setRootTitle(e.target.value)} />
              <Button type="button" size="sm" onClick={() => rootTitle.trim() && (onAction("mindmap.add_node", {mindmap_uri: uri, parent_id: "", title: rootTitle.trim()}), setRootTitle(""))}>
                <Plus className="h-4 w-4" /> 建根
              </Button>
            </div>
          ) : (
            <MindmapCanvas uri={uri} tree={tree} selectedId={selectedId} onSelectNode={setSelectedId} onAction={onAction} />
          )}
        </div>
      </div>
      <Status state={state} />
    </div>
  )
}

// 选中节点的属性面板（侧边栏）：认领 / 状态 / 阶段 / 产物 / 指标 / 改名 / 删除。
function NodePanel({node, args, stages, statuses, onAction}: {
  node: Node
  args: Record<string, unknown>
  stages: string[]
  statuses: string[]
  onAction: Act
}) {
  const owner = node.owner ? node.owner.split("/").pop() : null
  const selectCls = "rounded border border-border bg-background px-1 py-0.5 text-xs text-muted-foreground"
  return (
    <div className="flex flex-col gap-2 text-sm">
      <div className="font-medium text-foreground">{node.title}</div>
      <div className="flex flex-wrap items-center gap-1.5 text-xs text-muted-foreground">
        <span>{STATUS_ICON[node.status || "unassigned"]} {node.status || "未认领"}</span>
        {node.stage && <span className="rounded bg-muted px-1 text-primary">{STAGE_LABEL[node.stage] || node.stage}</span>}
        {owner && <span>@{owner}</span>}
      </div>
      <div className="flex flex-wrap items-center gap-1">
        <Button type="button" size="sm" variant="secondary" onClick={() => onAction("mindmap.claim_node", args)}>
          <Hand className="h-3.5 w-3.5" /> 认领
        </Button>
        <select className={selectCls} value="" onChange={(e) => e.target.value && onAction("mindmap.set_status", {...args, status: e.target.value})}>
          <option value="">状态…</option>
          {statuses.map((s) => (<option key={s} value={s}>{s}</option>))}
        </select>
        <select className={selectCls} value="" onChange={(e) => e.target.value && onAction("mindmap.set_stage", {...args, stage: e.target.value})}>
          <option value="">阶段…</option>
          {stages.map((s) => (<option key={s} value={s}>{STAGE_LABEL[s] || s}</option>))}
        </select>
      </div>
      <div>
        <div className="text-xs font-semibold text-muted-foreground">产物（{node.artifacts?.length ?? 0}）</div>
        <ul className="flex flex-col gap-0.5 text-xs text-muted-foreground">
          {(node.artifacts ?? []).map((a, i) => (
            <li key={i} className="truncate">📎 {String((a as Record<string, unknown>).ref ?? (a as Record<string, unknown>).tool ?? "artifact")}</li>
          ))}
        </ul>
        <button
          type="button"
          className="mt-1 inline-flex items-center gap-1 text-xs text-primary hover:underline"
          onClick={() => {
            const ref = window.prompt("产物引用（如 github PR #1）")
            if (ref) onAction("mindmap.attach_artifact", {...args, artifact: {tool: "github", kind: "pr", ref, url: ""}})
          }}
        >
          <Paperclip className="h-3 w-3" /> 加产物
        </button>
      </div>
      <div className="flex flex-wrap gap-2 border-t border-border pt-2 text-xs">
        <button
          type="button"
          className="inline-flex items-center gap-1 text-muted-foreground hover:text-foreground"
          onClick={() => {
            const name = window.prompt("指标名（如 周闭环数）")
            if (!name) return
            const target = window.prompt("目标值")
            onAction("mindmap.set_metric", {...args, metric: {name, target, current: null}})
          }}
        >
          <Target className="h-3 w-3" /> 设指标
        </button>
        <button
          type="button"
          className="inline-flex items-center gap-1 text-muted-foreground hover:text-foreground"
          onClick={() => {
            const t = window.prompt("新标题", node.title)
            if (t) onAction("mindmap.rename_node", {...args, title: t})
          }}
        >
          <Pencil className="h-3 w-3" /> 改名
        </button>
        <button
          type="button"
          className="inline-flex items-center gap-1 text-destructive hover:underline"
          onClick={() => onAction("mindmap.remove_node", args)}
        >
          <Trash2 className="h-3 w-3" /> 删除
        </button>
      </div>
    </div>
  )
}

function Status({state}: {state: MindmapState}) {
  if (!state.last_dispatch_status) return null
  const ok = state.last_dispatch_status === "ok"
  return <p className={`mt-2 text-xs ${ok ? "text-muted-foreground" : "text-destructive"}`}>· {state.last_dispatch_status}</p>
}
