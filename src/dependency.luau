local fs = require("@lune/fs")
local process = require("@lune/process")
local fsx = require("@project/fsx")
local tablex = require("@project/tablex")
local post = require("@project/post")
local dag = require("@project/dag")

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

function DependencyManager.add_dependency(self: DependencyManager, dep: Dependency): number
  local idx = dag.append_vertex(self.dag)
  table.insert(self.map, idx, dep)
  return idx
end

function DependencyManager.find_dependency(self: DependencyManager, dep: Dependency): number?
  local idx = table.find(self.map, dep)
  return idx
end

function DependencyManager.find_or_add_dependency(self: DependencyManager, dep: Dependency): number
  local idx = self:find_dependency(dep)
  if idx ~= nil then
    return idx
  else
    return DependencyManager.add_dependency(self, dep)
  end
end

function DependencyManager.add_output(self: DependencyManager, dep: DependencyOrIdx, name: string, output: any): number?
  local idx: number? = nil
  if typeof(dep) == "table" then
    idx = self:find_dependency(dep)
  else
    idx = dep :: number
  end
  if idx ~= nil then
    print("Adding output " .. name .. " for dep index " .. idx)
    self.store[idx] = { [name] = output; }
  end
  return idx
end

function DependencyManager.find_output(self: DependencyManager, dep: DependencyOrIdx): any?
  local idx: number? = nil
  if typeof(dep) == "table" then
    idx = self:find_dependency(dep)
  else
    idx = dep :: number
  end
  if idx ~= nil then
    return self.store[idx]
  else
    return nil
  end
end

function DependencyManager.visualize_graph(
    self: DependencyManager
  )
  local dot_graph_prefix = "digraph {\n"
  local dot_graph_suffix = "\n}"
  local input = dot_graph_prefix
  input = input .. "{\n"
  input = input .. "node [shape=box]\n"
  input = input .. "}\n"
  for i, edge in self.dag.edges do
    print(edge)
    local entry_from = self.map[edge.from]
    local entry_to = self.map[edge.to]
    if entry_from.file ~= nil and entry_from.file.path ~= nil then
      input = input .. " \"" .. entry_from.file.path .. "\""
    else
      input = input .. " pathless "
    end
    input = input .. "->"
    if entry_to.file ~= nil and entry_to.file.path ~= nil then
      input = input .. "\"" .. entry_to.file.path .. "\""
    else
      input = input .. " pathless "
    end
    input = input .. "\n"
  end
  input = input..dot_graph_suffix
  local graphviz_args = {
    "-Tsvg",
    "-Glabel='SSG output'",
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
  )
  local from_idx: number? = nil
  if typeof(from) == "table" then
    from_idx = DependencyManager.find_or_add_dependency(self, from :: Dependency)
  else
    from_idx = from :: number
  end

  local to_idx: number? = nil
  if typeof(to) == "table" then
    to_idx = DependencyManager.find_or_add_dependency(self, to :: Dependency)
  else
    to_idx = to :: number
  end

  if from_idx ~= nil and to_idx ~= nil then
    print("Associating " .. from_idx .. " to " .. to_idx .. " as kind " .. kind)
    dag.form_edge(self.dag, from_idx, to_idx, kind)
  end
end

return DependencyManager
