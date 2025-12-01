export type DAGEdge = {
  from: number,
  to: number,
  kind: string,
}


export type DAG = {
  edges: { DAGEdge },
  vertices: { number },
}

local dag = {}

function dag.create(): DAG
  local obj: DAG = {
    edges = {},
    vertices = {},
  }
  return obj
end

function dag.append_vertex(dag: DAG): number
  local idx = #dag.vertices+1
  table.insert(dag.vertices, idx)
  return idx
end

function dag.append_edge(dag: DAG, edge: DAGEdge)
  table.insert(dag.edges, edge)
end


function dag.create_edge(from: number, to: number, kind: string)
  local edge: DAGEdge = {
    from = from;
    to = to;
    kind = kind;
  }
  return edge
end

function dag.form_edge(obj: DAG, from: number, to: number, kind: string)
  local found = false
  for i, edge in obj["edges"] do
    print("testing")
    if edge.from == from and edge.to == to and edge.kind == kind then
      found = true
      break
    end
  end
  if not found then
    local edge = dag.create_edge(from, to, kind)
    dag.append_edge(obj, edge)
  else
    print("Dupes dupes dupes dupes")
  end
end

return dag
