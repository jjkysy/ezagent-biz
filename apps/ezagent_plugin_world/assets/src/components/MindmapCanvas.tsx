import {useCallback, useEffect, useMemo} from "react"
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

import {Plus} from "lucide-react"

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

// 9 阶段固定链的中文标签 + 顺序（顺序用于插入校验提示）。
export const STAGES = ["positioning", "metric", "pain", "anchor", "ux", "feature", "issue", "test", "pr"]
export const STAGE_LABEL: Record<string, string> = {
  positioning: "定位",
  metric: "北极星",
  pain: "痛点",
  anchor: "认领映射",
  ux: "线框",
  feature: "功能卡",
  issue: "issue",
  test: "测试",
  pr: "PR",
}

const NODE_W = 210
const NODE_H = 48

// 自定义节点卡片（react-flow 渲染的每个节点）。点击=选中（属性在侧边栏显示）。
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
      {node.stage && <span className="rounded bg-muted px-1 text-[10px] text-primary">{STAGE_LABEL[node.stage] || node.stage}</span>}
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

// 受控选择：selectedId / onSelectNode 由父组件（MindmapDetail）管，属性面板在侧边栏。
export function MindmapCanvas({uri, tree, selectedId, onSelectNode, onAction}: {
  uri: string
  tree: Tree
  selectedId: string | null
  onSelectNode: (id: string) => void
  onAction: Act
}) {
  const onAddChild = useCallback((id: string) => {
    const t = window.prompt("子节点标题")
    if (t && t.trim()) onAction("mindmap.add_node", {mindmap_uri: uri, parent_id: id, title: t.trim()})
  }, [onAction, uri])

  const laid = useMemo(() => layoutTree(tree, selectedId, onSelectNode, onAddChild), [tree, selectedId, onSelectNode, onAddChild])
  const [nodes, setNodes, onNodesChange] = useNodesState(laid.nodes)
  const [edges, setEdges, onEdgesChange] = useEdgesState(laid.edges)

  // 树/选中变化 → 重新布局（节点可拖，但结构变了重排）。
  useEffect(() => {
    setNodes(laid.nodes)
    setEdges(laid.edges)
  }, [laid, setNodes, setEdges])

  // react-flow 必须有显式尺寸——flex/百分比在 mount 时为 0 会让 fitView 失效、节点不可见。
  return (
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
  )
}
