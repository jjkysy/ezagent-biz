import React, {useMemo, useState} from "react"
import {
  CircleDot,
  ExternalLink,
  Hand,
  Paperclip,
  Pencil,
  Plus,
  RefreshCw,
  Target,
  Trash2,
} from "lucide-react"

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

const STATUS_ICON: Record<string, string> = {
  unassigned: "○",
  claimed: "◔",
  doing: "◑",
  done: "●",
}

export function Mindmap({
  state,
  onAction = () => undefined,
}: {
  state: MindmapState
  onAction?: Act
}) {
  if (!state.mindmap_uri) {
    return <MindmapList state={state} onAction={onAction} />
  }
  return <MindmapDetail state={state} onAction={onAction} />
}

function MindmapList({state, onAction}: {state: MindmapState; onAction: Act}) {
  const [name, setName] = useState("")
  const instances = state.instances || []

  return (
    <div className="world-surface" style={{padding: 24}}>
      <h2 className="world-heading">思维导图</h2>
      <p className="world-muted">每张导图是产品全链路的拓扑骨架；建树、认领、记状态、挂产物/指标，并一键镜像到 Miro。</p>

      <div style={{display: "flex", gap: 8, margin: "16px 0"}}>
        <input
          className="world-input"
          placeholder="新建导图名称（如 product-2026）"
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
        <button
          className="world-button"
          onClick={() => {
            if (name.trim()) {
              onAction("mindmap.create", {name: name.trim()})
              setName("")
            }
          }}
        >
          <Plus size={16} /> 新建
        </button>
      </div>

      {instances.length === 0 ? (
        <p className="world-muted">还没有导图，先新建一个。</p>
      ) : (
        <ul className="world-list">
          {instances.map((i) => (
            <li key={i.uri}>
              <a className="world-link" href={i.path}>
                {i.name} <span className="world-muted">— {i.uri}</span>
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
      const p = n.parent_id || "__root__"
      ;(map[p] ||= []).push(id)
    }
    for (const k of Object.keys(map)) {
      map[k].sort((a, b) => (tree.nodes[a].order || 0) - (tree.nodes[b].order || 0))
    }
    return map
  }, [tree])

  return (
    <div className="world-surface" style={{padding: 24}}>
      <div style={{display: "flex", justifyContent: "space-between", alignItems: "center"}}>
        <h2 className="world-heading">思维导图 · {uri.split("/").pop()}</h2>
        <div style={{display: "flex", gap: 8}}>
          <a className="world-link" href="/plugins/mindmap">← 全部导图</a>
          <button className="world-button" onClick={() => onAction("mindmap.sync_miro", {mindmap_uri: uri})}>
            <RefreshCw size={16} /> 推送到 Miro
          </button>
        </div>
      </div>

      {state.miro_board_url && (
        <p>
          <a className="world-link" href={state.miro_board_url} target="_blank" rel="noreferrer">
            <ExternalLink size={14} /> 打开 Miro 看板
          </a>
        </p>
      )}

      {!tree.root_id ? (
        <div style={{display: "flex", gap: 8, margin: "16px 0"}}>
          <input
            className="world-input"
            placeholder="根节点标题（产品发心）"
            value={rootTitle}
            onChange={(e) => setRootTitle(e.target.value)}
          />
          <button
            className="world-button"
            onClick={() => {
              if (rootTitle.trim()) {
                onAction("mindmap.add_node", {mindmap_uri: uri, parent_id: "", title: rootTitle.trim()})
                setRootTitle("")
              }
            }}
          >
            <Plus size={16} /> 建根
          </button>
        </div>
      ) : (
        <ul className="world-mindmap-tree" style={{listStyle: "none", paddingLeft: 0, marginTop: 16}}>
          <NodeRow
            id={tree.root_id}
            tree={tree}
            childrenOf={childrenOf}
            uri={uri}
            stages={stages}
            statuses={statuses}
            onAction={onAction}
            depth={0}
          />
        </ul>
      )}
      <Status state={state} />
    </div>
  )
}

function NodeRow({
  id,
  tree,
  childrenOf,
  uri,
  stages,
  statuses,
  onAction,
  depth,
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
  if (!n) return null
  const [childTitle, setChildTitle] = useState("")
  const [adding, setAdding] = useState(false)
  const kids = childrenOf[id] || []
  const owner = n.owner ? n.owner.split("/").pop() : null
  const args = {mindmap_uri: uri, id}

  return (
    <li style={{marginLeft: depth * 20, borderLeft: depth ? "1px solid var(--world-border, #2a2a2a)" : "none", paddingLeft: depth ? 12 : 0, marginTop: 8}}>
      <div style={{display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap"}}>
        <span title={n.status || ""}>{STATUS_ICON[n.status || "unassigned"]}</span>
        {n.stage && <span className="world-badge">[{n.stage}]</span>}
        <strong>{n.title}</strong>
        {owner && <span className="world-muted">@{owner}</span>}
        {(n.metrics?.length ?? 0) > 0 && <span className="world-muted"><Target size={12} /> {n.metrics!.length}</span>}
        {(n.artifacts?.length ?? 0) > 0 && <span className="world-muted"><Paperclip size={12} /> {n.artifacts!.length}</span>}

        {/* 操作区 */}
        <button className="world-icon-button" title="认领" onClick={() => onAction("mindmap.claim_node", args)}>
          <Hand size={14} />
        </button>
        <select
          className="world-input"
          value=""
          onChange={(e) => e.target.value && onAction("mindmap.set_status", {...args, status: e.target.value})}
        >
          <option value="">状态…</option>
          {statuses.map((s) => (<option key={s} value={s}>{s}</option>))}
        </select>
        <select
          className="world-input"
          value=""
          onChange={(e) => e.target.value && onAction("mindmap.set_stage", {...args, stage: e.target.value})}
        >
          <option value="">阶段…</option>
          {stages.map((s) => (<option key={s} value={s}>{s}</option>))}
        </select>
        <button className="world-icon-button" title="加子节点" onClick={() => setAdding((v) => !v)}>
          <Plus size={14} />
        </button>
        <button
          className="world-icon-button"
          title="挂产物"
          onClick={() => {
            const ref = window.prompt("产物引用（如 github PR #1）")
            if (ref) onAction("mindmap.attach_artifact", {...args, artifact: {tool: "github", kind: "pr", ref, url: ""}})
          }}
        >
          <Paperclip size={14} />
        </button>
        <button
          className="world-icon-button"
          title="设指标"
          onClick={() => {
            const name = window.prompt("指标名（如 周闭环数）")
            if (!name) return
            const target = window.prompt("目标值")
            onAction("mindmap.set_metric", {...args, metric: {name, target, current: null}})
          }}
        >
          <Target size={14} />
        </button>
        <button
          className="world-icon-button"
          title="改名"
          onClick={() => {
            const t = window.prompt("新标题", n.title)
            if (t) onAction("mindmap.rename_node", {...args, title: t})
          }}
        >
          <Pencil size={14} />
        </button>
        <button className="world-icon-button" title="删除（含子树）" onClick={() => onAction("mindmap.remove_node", args)}>
          <Trash2 size={14} />
        </button>
      </div>

      {adding && (
        <div style={{display: "flex", gap: 8, marginTop: 6}}>
          <input
            className="world-input"
            autoFocus
            placeholder="子节点标题"
            value={childTitle}
            onChange={(e) => setChildTitle(e.target.value)}
          />
          <button
            className="world-button"
            onClick={() => {
              if (childTitle.trim()) {
                onAction("mindmap.add_node", {mindmap_uri: uri, parent_id: id, title: childTitle.trim()})
                setChildTitle("")
                setAdding(false)
              }
            }}
          >
            加
          </button>
        </div>
      )}

      {kids.length > 0 && (
        <ul style={{listStyle: "none", paddingLeft: 0}}>
          {kids.map((cid) => (
            <NodeRow
              key={cid}
              id={cid}
              tree={tree}
              childrenOf={childrenOf}
              uri={uri}
              stages={stages}
              statuses={statuses}
              onAction={onAction}
              depth={depth + 1}
            />
          ))}
        </ul>
      )}
    </li>
  )
}

function Status({state}: {state: MindmapState}) {
  if (!state.last_dispatch_status) return null
  const ok = state.last_dispatch_status === "ok"
  return (
    <p className={ok ? "world-muted" : "world-error"} style={{marginTop: 16}}>
      <CircleDot size={12} /> {state.last_dispatch_status}
    </p>
  )
}
