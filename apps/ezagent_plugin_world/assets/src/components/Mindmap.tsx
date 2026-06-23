import React, {useMemo, useState} from "react"
import {ExternalLink, Hand, Paperclip, Pencil, Plus, RefreshCw, Target, Trash2} from "lucide-react"

import {Button} from "./ui/primitives"

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
  last_dispatch_status?: string | null
}

type Act = (action: string, args: Record<string, unknown>) => void

const STATUS_ICON: Record<string, string> = {unassigned: "○", claimed: "◔", doing: "◑", done: "●"}
const inputCls =
  "rounded-md border border-border bg-background px-2.5 py-1.5 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-ring"
const selectCls = "rounded-md border border-border bg-background px-1.5 py-1 text-xs text-muted-foreground"

export function Mindmap({state, onAction = () => undefined}: {state: MindmapState; onAction?: Act}) {
  return state.mindmap_uri ? (
    <MindmapDetail state={state} onAction={onAction} />
  ) : (
    <MindmapList state={state} onAction={onAction} />
  )
}

function MindmapList({state, onAction}: {state: MindmapState; onAction: Act}) {
  const [name, setName] = useState("")
  const instances = state.instances || []
  return (
    <div className="flex flex-col gap-4 p-6">
      <div>
        <h2 className="text-lg font-semibold text-foreground">思维导图</h2>
        <p className="text-sm text-muted-foreground">每张导图是产品全链路的拓扑骨架；建树、认领、记状态、挂产物/指标，并一键镜像到 Miro。</p>
      </div>
      <div className="flex gap-2">
        <input className={`${inputCls} w-72`} placeholder="新建导图名称（如 product-2026）" value={name} onChange={(e) => setName(e.target.value)} />
        <Button type="button" size="sm" onClick={() => name.trim() && (onAction("mindmap.create", {name: name.trim()}), setName(""))}>
          <Plus className="h-4 w-4" /> 新建
        </Button>
      </div>
      {instances.length === 0 ? (
        <p className="text-sm text-muted-foreground">还没有导图，先新建一个。</p>
      ) : (
        <ul className="flex flex-col gap-1">
          {instances.map((i) => (
            <li key={i.uri}>
              <a className="text-sm text-primary hover:underline" href={i.path}>
                {i.name} <span className="text-muted-foreground">— {i.uri}</span>
              </a>
            </li>
          ))}
        </ul>
      )}
      <Status state={state} />
    </div>
  )
}

function MindmapDetail({state, onAction}: {state: MindmapState; onAction: Act}) {
  const uri = state.mindmap_uri as string
  const tree = state.tree || {nodes: {}, root_id: null}
  const stages = state.stages || ["purpose", "value", "module", "feature", "dev", "ops"]
  const statuses = state.statuses || ["claimed", "doing", "done"]
  const [rootTitle, setRootTitle] = useState("")

  const childrenOf = useMemo(() => {
    const map: Record<string, string[]> = {}
    for (const [id, n] of Object.entries(tree.nodes)) {
      ;(map[n.parent_id || "__root__"] ||= []).push(id)
    }
    for (const k of Object.keys(map)) map[k].sort((a, b) => (tree.nodes[a].order || 0) - (tree.nodes[b].order || 0))
    return map
  }, [tree])

  return (
    <div className="flex flex-col gap-3 p-5">
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold text-foreground">思维导图 · {uri.split("/").pop()}</h2>
        <Button type="button" size="sm" variant="secondary" onClick={() => onAction("mindmap.sync_miro", {mindmap_uri: uri})}>
          <RefreshCw className="h-4 w-4" /> 推送到 Miro
        </Button>
      </div>
      {state.miro_board_url && (
        <a className="inline-flex items-center gap-1 text-sm text-primary hover:underline" href={state.miro_board_url} target="_blank" rel="noreferrer">
          <ExternalLink className="h-3.5 w-3.5" /> 打开 Miro 看板
        </a>
      )}
      {!tree.root_id ? (
        <div className="flex gap-2">
          <input className={`${inputCls} w-72`} placeholder="根节点标题（产品发心）" value={rootTitle} onChange={(e) => setRootTitle(e.target.value)} />
          <Button type="button" size="sm" onClick={() => rootTitle.trim() && (onAction("mindmap.add_node", {mindmap_uri: uri, parent_id: "", title: rootTitle.trim()}), setRootTitle(""))}>
            <Plus className="h-4 w-4" /> 建根
          </Button>
        </div>
      ) : (
        <ul className="mt-1 flex flex-col">
          <NodeRow id={tree.root_id} tree={tree} childrenOf={childrenOf} uri={uri} stages={stages} statuses={statuses} onAction={onAction} depth={0} />
        </ul>
      )}
      <Status state={state} />
    </div>
  )
}

function IconBtn({title, onClick, children}: {title: string; onClick: () => void; children: React.ReactNode}) {
  return (
    <button type="button" title={title} onClick={onClick} className="rounded p-1 text-muted-foreground hover:bg-muted hover:text-foreground">
      {children}
    </button>
  )
}

function NodeRow({
  id, tree, childrenOf, uri, stages, statuses, onAction, depth,
}: {
  id: string
  tree: Tree
  childrenOf: Record<string, string[]>
  uri: string
  stages: string[]
  statuses: string[]
  onAction: Act
  depth: number
}) {
  const n = tree.nodes[id]
  const [childTitle, setChildTitle] = useState("")
  const [adding, setAdding] = useState(false)
  if (!n) return null
  const kids = childrenOf[id] || []
  const owner = n.owner ? n.owner.split("/").pop() : null
  const args = {mindmap_uri: uri, id}

  return (
    <li style={{marginLeft: depth * 18}} className={depth ? "border-l border-border pl-3" : ""}>
      <div className="flex flex-wrap items-center gap-1.5 py-1 text-sm text-foreground">
        <span title={n.status || ""} className="text-muted-foreground">{STATUS_ICON[n.status || "unassigned"]}</span>
        {n.stage && <span className="rounded bg-muted px-1.5 py-0.5 text-[11px] text-primary">[{n.stage}]</span>}
        <strong className="font-medium">{n.title}</strong>
        {owner && <span className="text-xs text-muted-foreground">@{owner}</span>}
        {(n.metrics?.length ?? 0) > 0 && <span className="inline-flex items-center gap-0.5 text-xs text-muted-foreground"><Target className="h-3 w-3" />{n.metrics!.length}</span>}
        {(n.artifacts?.length ?? 0) > 0 && <span className="inline-flex items-center gap-0.5 text-xs text-muted-foreground"><Paperclip className="h-3 w-3" />{n.artifacts!.length}</span>}

        <IconBtn title="认领" onClick={() => onAction("mindmap.claim_node", args)}><Hand className="h-3.5 w-3.5" /></IconBtn>
        <select className={selectCls} value="" onChange={(e) => e.target.value && onAction("mindmap.set_status", {...args, status: e.target.value})}>
          <option value="">状态…</option>
          {statuses.map((s) => (<option key={s} value={s}>{s}</option>))}
        </select>
        <select className={selectCls} value="" onChange={(e) => e.target.value && onAction("mindmap.set_stage", {...args, stage: e.target.value})}>
          <option value="">阶段…</option>
          {stages.map((s) => (<option key={s} value={s}>{s}</option>))}
        </select>
        <IconBtn title="加子节点" onClick={() => setAdding((v) => !v)}><Plus className="h-3.5 w-3.5" /></IconBtn>
        <IconBtn title="挂产物" onClick={() => {
          const ref = window.prompt("产物引用（如 github PR #1）")
          if (ref) onAction("mindmap.attach_artifact", {...args, artifact: {tool: "github", kind: "pr", ref, url: ""}})
        }}><Paperclip className="h-3.5 w-3.5" /></IconBtn>
        <IconBtn title="设指标" onClick={() => {
          const name = window.prompt("指标名（如 周闭环数）")
          if (!name) return
          const target = window.prompt("目标值")
          onAction("mindmap.set_metric", {...args, metric: {name, target, current: null}})
        }}><Target className="h-3.5 w-3.5" /></IconBtn>
        <IconBtn title="改名" onClick={() => {
          const t = window.prompt("新标题", n.title)
          if (t) onAction("mindmap.rename_node", {...args, title: t})
        }}><Pencil className="h-3.5 w-3.5" /></IconBtn>
        <IconBtn title="删除（含子树）" onClick={() => onAction("mindmap.remove_node", args)}><Trash2 className="h-3.5 w-3.5" /></IconBtn>
      </div>

      {adding && (
        <div className="mb-1 flex gap-2">
          <input className={inputCls} autoFocus placeholder="子节点标题" value={childTitle} onChange={(e) => setChildTitle(e.target.value)} />
          <Button type="button" size="sm" onClick={() => childTitle.trim() && (onAction("mindmap.add_node", {mindmap_uri: uri, parent_id: id, title: childTitle.trim()}), setChildTitle(""), setAdding(false))}>加</Button>
        </div>
      )}

      {kids.length > 0 && (
        <ul className="flex flex-col">
          {kids.map((cid) => (
            <NodeRow key={cid} id={cid} tree={tree} childrenOf={childrenOf} uri={uri} stages={stages} statuses={statuses} onAction={onAction} depth={depth + 1} />
          ))}
        </ul>
      )}
    </li>
  )
}

function Status({state}: {state: MindmapState}) {
  if (!state.last_dispatch_status) return null
  const ok = state.last_dispatch_status === "ok"
  return <p className={`mt-2 text-xs ${ok ? "text-muted-foreground" : "text-destructive"}`}>· {state.last_dispatch_status}</p>
}
