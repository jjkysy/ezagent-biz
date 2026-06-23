import React, {useState} from "react"
import {ExternalLink, Plus, RefreshCw} from "lucide-react"

import {Button} from "./ui/primitives"
import {MindmapCanvas} from "./MindmapCanvas"

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

export function Mindmap({state, onAction = () => undefined}: {state: MindmapState; onAction?: Act}) {
  return state.mindmap_uri ? (
    <MindmapDetail state={state} onAction={onAction} />
  ) : (
    <MindmapList state={state} onAction={onAction} />
  )
}

// 插件配置页 = 只配 Miro 凭证（不在这编辑导图——编辑在会话内 Mindmap 子视图）。
function MindmapList({state, onAction}: {state: MindmapState; onAction: Act}) {
  const [token, setToken] = useState("")
  const [board, setBoard] = useState(state.miro?.board_id || "")
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
        <label className="flex flex-col gap-1 text-xs text-muted-foreground">
          Board ID（可选，留空则每次自动新建板）
          <input className={`${inputCls} w-full`} placeholder="board id" value={board} onChange={(e) => setBoard(e.target.value)} />
        </label>
        <div>
          <Button type="button" size="sm" onClick={() => token.trim() && onAction("mindmap.save_miro_creds", {access_token: token.trim(), board_id: board.trim()})}>
            保存凭证
          </Button>
        </div>
        <p className="text-xs text-muted-foreground">凭证存到 system://credentials/miro.yaml（节点级，0600，仅 admin 可改）。不配也能用，只是会话内不同步。</p>
      </div>
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

  return (
    <div className="flex h-full flex-col gap-3 p-5">
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
        // 可拖动视觉树（react-flow + dagre 自动布局，像 Miro/xmind）。
        <div className="overflow-hidden rounded-md border border-border">
          <MindmapCanvas uri={uri} tree={tree} stages={stages} statuses={statuses} onAction={onAction} />
        </div>
      )}
      <Status state={state} />
    </div>
  )
}

function Status({state}: {state: MindmapState}) {
  if (!state.last_dispatch_status) return null
  const ok = state.last_dispatch_status === "ok"
  return <p className={`mt-2 text-xs ${ok ? "text-muted-foreground" : "text-destructive"}`}>· {state.last_dispatch_status}</p>
}
