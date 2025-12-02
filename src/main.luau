local fs = require("@lune/fs")
local serde = require("@lune/serde")
local regex = require("@lune/regex")

local post = require("@project/post")
local template = require("@project/template")
local fsx = require("@project/fsx")
local tablex = require("@project/tablex")
local DependencyManager = require("@project/dependency")

local option = require("@rustyluau/option")
local Option = option.Option
type Option<T> = option.Option<T>
local None = option.None
local Some = option.Some

local main = {}

function load_site_config()
  print("Loading site config")
  local config = serde.decode("toml", fs.readFile("./config.toml"))
  print("Site config loaded")
  print(config)
  return config
end

--[[
-- this filter has a build stage because it allows for precompilation of the
-- regular expressions a single time by using it within scope. i think it's
-- really cute.
]]--
function build_filter(): (string) -> boolean
    local excludes = {
      "^\\..+$",
      "\/\\..+$",
      ".*.nix$",
      ".*.lock$",
      "README.md",
      "TODO.md",
      "third-party",
    }
    local pattern_excludes = {}
    for _, raw_pattern in ipairs(excludes) do
      local pattern = regex.new(raw_pattern)
      table.insert(pattern_excludes, pattern)
    end
    -- the actual filter, is of course this, and a similar mechanism lives
    -- within the actual filter handler
    local function filetree_filter(path: string): boolean
      local add_to_files = true
      for _, pattern in pattern_excludes do
        if pattern:isMatch(path) then
          add_to_files = false
          break
        end
      end
      return add_to_files
    end
    return filetree_filter
end

function post_remapper(config: tablex.TableWildcard, path: string, filetype: string): string
  local result = config.result_dir .. "/"
  local moved_dir = string.gsub(path, "content/", result)
  local refiletyped = string.gsub(moved_dir, filetype, "html")
  return refiletyped
end

--[[
-- To understand a dependency relationship, we need knowledge of:
-- * how should the output path change at the terminus?
-- * how should the dependency (and its dependents) be obtained from the rft?
--   * handled by the GFR system
-- * how should the output itself be created?
]]--


function build_root(
    depmgr: DependencyManager.DependencyManager,
    parents: { [string]: DependencyManager.DependencyOrIdx },
    me: DependencyManager.DependencyOrIdx,
    sft: fsx.FiletreeOutput,
    f: fsx.FileMetadata
  ): ()
  for i, parent in parents do
    local html_output = depmgr:find_output(parent, "html")
    if html_output:isSome() then
      local new_path = post_remapper(depmgr.config, f.path:unwrap(), f.filetype:unwrap())
      fsx.produce_file(new_path, html_output:unwrap())
    end
  end
end

function build_template(
    depmgr: DependencyManager.DependencyManager,
    parents: { [string]: DependencyManager.DependencyOrIdx },
    me: DependencyManager.DependencyOrIdx,
    sft: fsx.FiletreeOutput,
    f: fsx.FileMetadata
  ): ()
  local template_parsed = template.parse(f.path:unwrap())
  depmgr:add_output(me, "template", template_parsed)
end

function build_post(
    depmgr: DependencyManager.DependencyManager,
    parents: { [string]: DependencyManager.DependencyOrIdx },
    me: DependencyManager.DependencyOrIdx,
    sft: fsx.FiletreeOutput,
    f: fsx.FileMetadata
  ): ()

  local tpl = None()
  for i, parent in parents do
    tpl = depmgr:find_output(parent, "template")
    if tpl:isSome() then
      break
    end
  end
  if tpl:isSome() then
    local post = depmgr:find_output(me, "post")
    if post ~= nil then
      local context = {
        post = post,
        config = depmgr.config,
      }
      local tplo: (...any) -> ...any = tpl:unwrap()
      local templated = tplo(context)
      depmgr:add_output(me, "html", templated)
    end
  end
end

function parse_post(
    path: string,
    format: string
  ): Option<post.Post>
  local post_obj = post.parse(format, path)
  return post_obj
end

function create_post_dependency(
    depmgr: DependencyManager.DependencyManager,
    fm: fsx.FileMetadata,
    format: string
  ): Option<DependencyManager.DependencyOrIdx>
  local post_dep: DependencyManager.Dependency = {
    build = build_post,
    file = Some(fm),
  }
  local idx = depmgr:add_dependency(post_dep)
  return idx:andThen(function(_)
    local post_obj = parse_post(fm.path:unwrap(), format)
    return post_obj:map(function(post_objj)
      depmgr:add_output(post_dep, "post", post_objj)
      return post_dep
    end)
  end)
end

function get_template_from_post(
    post_obj: post.Post,
    default_template: string?
  ): Option<string>
  local pfm = post_obj.frontmatter
  local result = None()
  if pfm ~= nil and pfm.template ~= nil then
    print("nyaaaa")
    print(pfm.template)
    result = Some(pfm.template)
  else
    result = Some(default_template)
  end
  return result:map(function(st)
    return "./templates/" .. st
  end)
end

function get_template_file_from_post_dependency(
    depmgr: DependencyManager.DependencyManager,
    post_dep: DependencyManager.DependencyOrIdx,
    default_template: string?
): Option<fsx.FileMetadata>
  local post_obj = depmgr:find_output(post_dep, "post")
  if post_obj:isSome() then
    local po = post_obj:unwrap()
    print(po)
    local template_filename = get_template_from_post(po, default_template)
    if template_filename:isSome() then
      return depmgr:get_by_path(template_filename:unwrap())
    end
  end
  return None()
end

function create_template_dependency(
    depmgr: DependencyManager.DependencyManager,
    post_dep: DependencyManager.DependencyOrIdx,
    default_template: string?
): DependencyManager.DependencyOrIdx
  local fm = get_template_file_from_post_dependency(depmgr, post_dep, default_template)
  local tpl_dep: DependencyManager.Dependency = {
    build = build_template,
    file = fm,
  }
  local idx = depmgr:find_or_add_dependency(tpl_dep)
  return idx
end

--[[
-- TODO: remove all complexity that arises as a result of Zola compatibility where it doesn't concern frontmatter
--
-- like, template configuration doesn't need to be done via _index.md, Zola didn't have a scripting language: we do
]]--

function handle_post_dependency(filetype: string, format: string): (string, DependencyManager.GraphFormerRule)
  local function graph_former_rule(
    depmgr: DependencyManager.DependencyManager,
    parent: DependencyManager.DependencyOrIdx,
    sft: fsx.FiletreeOutput,
    f: fsx.FileMetadata
  ): ()
    if f.filetype:isSomeAnd(function(f)
      return f == filetype
      end)
    then
      local post_dependency = create_post_dependency(depmgr, f, format)
      post_dependency:inspect(function(pd)
        depmgr:add_association(1, pd, "post")
        local td = create_template_dependency(depmgr, pd, "post.tpl")
        depmgr:add_association(pd, td, "template")
      end)
    end
  end

  return filetype .. "_handler", graph_former_rule
end

function main.call()
  local config = load_site_config()

  local tree_filter = build_filter()
  local filetree_config: fsx.FiletreeConfig = {
    filters = {
      tree_filter
    },
  }

  local rft: fsx.FiletreeOutput = fsx.build_filetree("./", filetree_config)

  local depmgr = DependencyManager.new(config, rft)

  local md_name, md_func = handle_post_dependency("md", "markdown_mmd")
  depmgr:add_gfr(md_name, md_func)
  depmgr:add_root(build_root)
  depmgr:build_graph()
  depmgr:visualize_graph()
  --depmgr:build_all()
  print(depmgr.map)
  --mapper.build_dependency_graph(filetree, filetree)

  --local _posts = post.handle_all()
  --local _templates = template.handle_all(config)
  --[[local tree_filter = build_filter()
  local filetree_config: fsx.FiletreeConfig = {
    filters = {
      tree_filter
    },
  }
  local recipes: { [string]: (...any) -> ...any } = {}
  local markdown_source = build_markdown_source(config)
  local markdown_chain: (...any) -> ...any = build_markdown_chain(markdown_source)
  local unbuilt_recipes: { [string]: (...any) -> ...any } = {
    template_source = build_template_source
  }
  for k, unbuilt_recipe in unbuilt_recipes do
    recipes[k] = unbuilt_recipe(config)
  end
  recipes["markdown_chain"] = markdown_chain
  local filetree: fsx.FiletreeOutput = fsx.build_filetree("./", filetree_config)
  apply_recipes(filetree, recipes)
  --print(templates)
  --print(markdown_contexts)]]--
end

return main
