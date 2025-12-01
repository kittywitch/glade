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
  local edge = dag.create_edge(from, to, kind)
  dag.append_edge(obj, edge)
end

function dag.get_children_of_node(obj: DAG, vertex: number)
  local children = {}
  for i, edge: any in obj.edges do
    if edge["to"] ~= nil and edge["to"] == vertex then
      table.insert(children, edge["from"])
    end
  end
end

function dag.podfs(obj: DAG, consumer: (...any) -> any)
  for i, edge in dag.get_children_of_node(obj, 1)  do

  end
end

return dag
