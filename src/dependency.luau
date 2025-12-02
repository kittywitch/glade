local fs = require("@lune/fs")
local process = require("@lune/process")
local fsx = require("@project/fsx")
local tablex = require("@project/tablex")
local post = require("@project/post")
local dag = require("@project/dag")

local option = require("@rustyluau/option")

type Option<T> = option.Option<T>
local Option, Some, None = option.Option, option.Some, option.None

export type Dependency = {
  -- all dependencies are buildable
  build: ((...any) -> ...any)?,
  file: fsx.FileMetadata?,
}

export type DependencyOrIdx = Dependency | number

export type DependencyManagerOutput = { [string]: any }

export type DependencyManagerOutputStore = {
  [number]: DependencyManagerOutput
}

export type DependencyMap = { Dependency }

export type GraphFormerRule = (
  depmgr: DependencyManager,
  parent: DependencyOrIdx,
  sft: fsx.FiletreeOutput,
  f: fsx.FileMetadata
) -> ()

export type GraphFormerRules = {
  [string]: GraphFormerRule
}

type DependencyManagerData = {
  rft: fsx.FiletreeOutput,
  gfr: GraphFormerRules,
  dag: dag.DAG,
  map: DependencyMap,
  config: any,
  store: DependencyManagerOutputStore,
}

local DependencyManager = {}
DependencyManager.__index = DependencyManager

export type DependencyManager = typeof(
  setmetatable(
    {} :: DependencyManagerData,
    DependencyManager
  )
)

function DependencyManager.new(
    config: any,
    rft: fsx.FiletreeOutput
  ): DependencyManager
  local self = {}
  self.rft = rft
  self.dag = dag.create()
  self.config = config
  self.gfr = {}
  self.map = {}
  self.store = {}

  return setmetatable(self, DependencyManager)
end

function DependencyManager.add_root(self: DependencyManager, handler: (...any) -> ...any)
  local root_dependency: Dependency = {
    build = handler,
  }
  dag.append_vertex(self.dag)
  table.insert(self.map, root_dependency)
end

--[[
-- Graph former rules (or GFRs) are what constructs the DAG and dependency map from the filetree
]]--

function DependencyManager.add_gfr(self: DependencyManager, name: string, gfr: GraphFormerRule)
  print("Registered handler " .. name)
  self.gfr[name] = gfr
end

--[[
-- End GFR section
]]--

function DependencyManager.build_graph(self: DependencyManager)
  print("Beginning dependency graph build")
  local root = self.map[1]
  local function recursive_graph_builder(rft: fsx.FiletreeOutput, ft: fsx.FiletreeOutput)
    for sp, e in ft.files do
      for gfrn, gfr in self.gfr do
        print("Running gfr " .. gfrn .. " against " .. sp)
        gfr(self, root, ft, e)
      end
    end
    for sp, e in ft.dirs do
      print("Recursing to " .. sp)
      recursive_graph_builder(self.rft, e)
    end
  end
  recursive_graph_builder(self.rft, self.rft)
end

function DependencyManager.add_dependency(self: DependencyManager, dep: Dependency): option.Option<number>
  if self:find_dependency(dep):isSome() then
    return None()
  else
    local idx = dag.append_vertex(self.dag)
    table.insert(self.map, idx, dep)
    return Some(idx)
  end
end

-- TODO: not checking length of dep1 and dep2, incomplete
function check_equal(dep1: Dependency, dep2: Dependency)
  if dep1 == dep2 then
    return true
  end
  local equal = true
  for k, v in dep1 do
    if dep2[k] ~= v then
      equal = false
    end
  end
  if equal then
    return equal
  end
  return false
end

function DependencyManager.get_dependency(self: DependencyManager, idx: number): Option<Dependency>
  return Option.new(self.map[idx])
end

function DependencyManager.find_dependency(self: DependencyManager, dep: Dependency): Option<number>
  local idx = table.find(self.map, dep)
  for i, j in self.map do
    if check_equal(dep, j) then
      idx = i
      break
    end
  end
  return Option.new(idx)
end

function DependencyManager.get_dep_idx(self: DependencyManager, val: DependencyOrIdx): Option<number>
  local idx: Option<number> = nil
  if typeof(val) == "table" then
    idx = self:find_dependency(val)
  else
    idx = Some(val)
  end
  return idx
end

function DependencyManager.find_or_add_dependency(self: DependencyManager, dep: Dependency): number
  local idx = self:find_dependency(dep)
  local function lazy_add(): Option<number>
    return self:add_dependency(dep)
  end
  -- if you can neither add it, or find it, you fucked up somehow I think
  return idx:orElse(lazy_add):unwrap()
end

function DependencyManager.add_output(self: DependencyManager, dep: DependencyOrIdx, name: string, output: any): boolean
  local idx: Option<number> = self:get_dep_idx(dep)
  return idx:map(function(idxx: number): boolean
    print("Adding output " .. name .. " for dep index " .. idxx)
    if self.store[idxx] == nil then
      self.store[idxx] = {}
    end
    self.store[idxx][name] = output
    return true
  end):unwrapOr(false)
end

function DependencyManager.find_output(self: DependencyManager, dep: DependencyOrIdx, name: string): Option<any>
  local idx: Option<number> = self:get_dep_idx(dep)
  return idx:map(function(idxx: number): Option<any>
    return Option.new(self.store[idxx][name])
  end)
end

function DependencyManager.get_outputs(self: DependencyManager, dep: DependencyOrIdx): Option<any>
  local idx: Option<number> = self:get_dep_idx(dep)
  return idx:map(function(idxx: number): Option<any>
    return Option.new(self.store[idxx])
  end)
end

function DependencyManager.visualize_graph(
    self: DependencyManager
  )
  local dot_graph_prefix = "digraph {\n"
  local dot_graph_suffix = "\n}"
  local input = dot_graph_prefix
  input = input .. "rankdir=LR\n"
  input = input .. "node [shape=box]\n"
  input = input .. "root [shape=diamond]\n"
  for i, edge in self.dag.edges do
    print(edge)
    local entry_from = self.map[edge.from]
    local entry_to = self.map[edge.to]
    if edge.to == 1 then
      input = input .. " root "
    elseif entry_to.file ~= nil and entry_to.file.path ~= nil then
      input = input .. "\"" .. entry_to.file.path .. "\""
    else
      input = input .. " pathless "
    end
    input = input .. "->"
    if edge.from == 1 then
      input = input .. " root "
    elseif entry_from.file ~= nil and entry_from.file.path ~= nil then
      input = input .. " \"" .. entry_from.file.path .. "\""
    else
      input = input .. " pathless "
    end
    input = input .. "\n"
  end
  input = input..dot_graph_suffix
  local graphviz_args = {
    "-Tsvg",
    "-Glabel=SSG output",
  }
  local exec_opts: process.ExecOptions = {
    cwd = process.env["REPO_ROOT"],
    stdio = {
      stdin = input
    },
  }

  print(input)
  local graphviz_result = process.exec("dot", graphviz_args, exec_opts)
  if graphviz_result.ok then
    print("Graph output successful.")
    fs.writeFile("ssg_graph.svg", graphviz_result.stdout)
  end
end

function DependencyManager.add_association(
    self: DependencyManager,
    from: DependencyOrIdx,
    to: DependencyOrIdx,
    kind: string
  ): boolean
  local from_idx: Option<number> = self:get_dep_idx(from)
  local to_idx: Option<number> = self:get_dep_idx(to)
  return from_idx:zip(to_idx):map(function(idx)
    dag.form_edge(self.dag, idx[1], idx[2], kind)
    return true
  end):unwrapOr(false)
end

function DependencyManager.get_by_path(
  self: DependencyManager,
  path: string
): Option<fsx.FileMetadata>
  return fsx.get_by_path(self.rft, path)
end

function DependencyManager.build_all(self: DependencyManager)
  local marked = {}
  local can_find_next = true
  local edge_focus = self.dag.edges[1]
  local vertex_focus = edge_focus.to
  for i, edge in self.dag.edges do
    if edge.from == vertex_focus then
      edge_focus = edge
      vertex_focus = edge.to
    end
  end
  print(edge_focus)
  print(vertex_focus)
end

return DependencyManager
