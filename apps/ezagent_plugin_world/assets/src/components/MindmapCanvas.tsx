import React, {useCallback, useEffect, useMemo, useState} from "react"
import {
  Background,
  Controls,
  Handle,
  Position,
  ReactFlow,
  useEdgesState,
  useNodesState,
  type Edge,
  type Node as FlowNode,
} from "@xyflow/react"
import dagre from "dagre"
import "@xyflow/react/dist/style.css"

import {Button} from "./ui/primitives"
import {Hand, Paperclip, Pencil, Plus, Target, Trash2} from "lucide-react"

type Node = {
  parent_id: string | null
  title: string
  order: number
  stage: string | null
  owner: string | null
  status: string | null
  artifacts?: unknown[]
  metrics?: unknown[]
}
type Tree = {nodes: Record<string, Node>; root_id: string | null}
type Act = (action: string, args: Record<string, unknown>) => void

const STATUS_ICON: Record<string, string> = {unassigned: "○", claimed: "◔", doing: "◑", done: "●"}
const NODE_W = 210
const NODE_H = 48

// 自定义节点卡片（react-flow 渲染的每个节点）。
function MmNode({data}: {data: {node: Node; id: string; selected: boolean; onSelect: (id: string) => void; onAddChild: (id: string) => void}}) {
  const {node, id, selected, onSelect, onAddChild} = data
  const owner = node.owner ? node.owner.split("/").pop() : null
  return (
    <div
      onClick={() => onSelect(id)}
      className={`flex items-center gap-1.5 rounded-md border bg-card px-2.5 py-2 text-sm shadow-sm transition ${selected ? "border-primary ring-1 ring-primary" : "border-border"}`}
      style={{width: NODE_W, minHeight: NODE_H}}
    >
      <Handle type="target" position={Position.Left} className="!bg-border" />
      <span className="text-muted-foreground">{STATUS_ICON[node.status || "unassigned"]}</span>
      {node.stage && <span className="rounded bg-muted px-1 text-[10px] text-primary">{node.stage}</span>}
      <span className="flex-1 truncate font-medium text-foreground" title={node.title}>{node.title}</span>
      {owner && <span className="text-[10px] text-muted-foreground">@{owner}</span>}
      <button
        type="button"
        title="加子节点"
        onClick={(e) => {e.stopPropagation(); onAddChild(id)}}
        className="rounded p-0.5 text-muted-foreground hover:bg-muted hover:text-foreground"
      >
        <Plus className="h-3.5 w-3.5" />
      </button>
      <Handle type="source" position={Position.Right} className="!bg-border" />
    </div>
  )
}

const nodeTypes = {mm: MmNode}

function layoutTree(tree: Tree, selectedId: string | null, onSelect: (id: string) => void, onAddChild: (id: string) => void): {nodes: FlowNode[]; edges: Edge[]} {
  const ids = Object.keys(tree.nodes)
  if (ids.length === 0) return {nodes: [], edges: []}
  const g = new dagre.graphlib.Graph()
  g.setGraph({rankdir: "LR", nodesep: 16, ranksep: 70})
  g.setDefaultEdgeLabel(() => ({}))
  for (const id of ids) g.setNode(id, {width: NODE_W, height: NODE_H})
  for (const [id, n] of Object.entries(tree.nodes)) if (n.parent_id && tree.nodes[n.parent_id]) g.setEdge(n.parent_id, id)
  dagre.layout(g)

  const nodes: FlowNode[] = ids.map((id) => {
    const pos = g.node(id)
    return {
      id,
      type: "mm",
      position: {x: pos.x - NODE_W / 2, y: pos.y - NODE_H / 2},
      data: {node: tree.nodes[id], id, selected: id === selectedId, onSelect, onAddChild},
    }
  })
  const edges: Edge[] = Object.entries(tree.nodes)
    .filter(([, n]) => n.parent_id && tree.nodes[n.parent_id!])
    .map(([id, n]) => ({id: `${n.parent_id}-${id}`, source: n.parent_id!, target: id, type: "smoothstep"}))
  return {nodes, edges}
}

export function MindmapCanvas({uri, tree, stages, statuses, onAction}: {
  uri: string
  tree: Tree
  stages: string[]
  statuses: string[]
  onAction: Act
}) {
  const [selectedId, setSelectedId] = useState<string | null>(tree.root_id)
  const onSelect = useCallback((id: string) => setSelectedId(id), [])
  const onAddChild = useCallback((id: string) => {
    const t = window.prompt("子节点标题")
    if (t && t.trim()) onAction("mindmap.add_node", {mindmap_uri: uri, parent_id: id, title: t.trim()})
  }, [onAction, uri])

  const laid = useMemo(() => layoutTree(tree, selectedId, onSelect, onAddChild), [tree, selectedId, onSelect, onAddChild])
  const [nodes, setNodes, onNodesChange] = useNodesState(laid.nodes)
  const [edges, setEdges, onEdgesChange] = useEdgesState(laid.edges)

  // 树/选中变化 → 重新布局（节点可拖，但结构变了重排）。
  useEffect(() => {
    setNodes(laid.nodes)
    setEdges(laid.edges)
  }, [laid, setNodes, setEdges])

  const sel = selectedId ? tree.nodes[selectedId] : null
  const args = selectedId ? {mindmap_uri: uri, id: selectedId} : {}

  return (
    <div className="flex flex-col">
      {/* 选中节点工具栏 */}
      {sel && (
        <div className="flex flex-wrap items-center gap-1.5 border-b border-border bg-muted/40 px-3 py-1.5 text-sm">
          <span className="text-muted-foreground">选中：</span>
          <strong className="text-foreground">{sel.title}</strong>
          <button type="button" title="认领" onClick={() => onAction("mindmap.claim_node", args)} className="rounded p-1 hover:bg-muted"><Hand className="h-3.5 w-3.5" /></button>
          <select className="rounded border border-border bg-background px-1 py-0.5 text-xs" value="" onChange={(e) => e.target.value && onAction("mindmap.set_status", {...args, status: e.target.value})}>
            <option value="">状态…</option>
            {statuses.map((s) => (<option key={s} value={s}>{s}</option>))}
          </select>
          <select className="rounded border border-border bg-background px-1 py-0.5 text-xs" value="" onChange={(e) => e.target.value && onAction("mindmap.set_stage", {...args, stage: e.target.value})}>
            <option value="">阶段…</option>
            {stages.map((s) => (<option key={s} value={s}>{s}</option>))}
          </select>
          <button type="button" title="挂产物" onClick={() => {const r = window.prompt("产物引用（如 github PR #1）"); if (r) onAction("mindmap.attach_artifact", {...args, artifact: {tool: "github", kind: "pr", ref: r, url: ""}})}} className="rounded p-1 hover:bg-muted"><Paperclip className="h-3.5 w-3.5" /></button>
          <button type="button" title="设指标" onClick={() => {const n = window.prompt("指标名"); if (!n) return; const tg = window.prompt("目标值"); onAction("mindmap.set_metric", {...args, metric: {name: n, target: tg, current: null}})}} className="rounded p-1 hover:bg-muted"><Target className="h-3.5 w-3.5" /></button>
          <button type="button" title="改名" onClick={() => {const t = window.prompt("新标题", sel.title); if (t) onAction("mindmap.rename_node", {...args, title: t})}} className="rounded p-1 hover:bg-muted"><Pencil className="h-3.5 w-3.5" /></button>
          <button type="button" title="删除（含子树）" onClick={() => onAction("mindmap.remove_node", args)} className="rounded p-1 text-destructive hover:bg-muted"><Trash2 className="h-3.5 w-3.5" /></button>
        </div>
      )}
      {/* react-flow 必须有显式尺寸——flex/百分比在 mount 时为 0 会让 fitView 失效、节点不可见 */}
      <div style={{height: 480, width: "100%"}}>
        <ReactFlow
          nodes={nodes}
          edges={edges}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          nodeTypes={nodeTypes}
          fitView
          fitViewOptions={{padding: 0.2, maxZoom: 1}}
          minZoom={0.2}
          proOptions={{hideAttribution: true}}
        >
          <Background />
          <Controls showInteractive={false} />
        </ReactFlow>
      </div>
    </div>
  )
}
