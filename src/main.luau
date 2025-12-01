local fs = require("@lune/fs")
local serde = require("@lune/serde")
local regex = require("@lune/regex")

local post = require("@project/post")
local template = require("@project/template")
local fsx = require("@project/fsx")
local tablex = require("@project/tablex")
local dag = require("@project/dag")
local DependencyManager = require("@project/dependency")

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
    if html_output ~= nil then
      local new_path = post_remapper(depmgr.config, f.path, f.filetype)
      fsx.produce_file(new_path, html_output)
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
  local template_parsed = template.parse(f.path)
  depmgr:add_output(me, "template", template_parsed)
end

function build_post(
    depmgr: DependencyManager.DependencyManager,
    parents: { [string]: DependencyManager.DependencyOrIdx },
    me: DependencyManager.DependencyOrIdx,
    sft: fsx.FiletreeOutput,
    f: fsx.FileMetadata
  ): ()

  local tpl = nil
  for i, parent in parents do
    tpl = depmgr:find_output(parent, "template")
    if tpl ~= nil then
      break
    end
  end
  if tpl ~= nil then
    local post = depmgr:find_output(me, "post")
    if post ~= nil then
      local context = {
        post = post,
        config = depmgr.config,
      }
      local templated = tpl(context)
      depmgr:add_output(me, "html", templated)
    end
  end
end

function parse_post(
    path: string,
    format: string
  ): post.Post?
  local post_obj = post.parse(format, path)
  return post_obj
end

function create_post_dep(
    depmgr: DependencyManager.DependencyManager,
    fm: fsx.FileMetadata,
    format: string,
    template: boolean
  ): (DependencyManager.Dependency, post.Post?, string?)
  local post_dep: DependencyManager.Dependency = {
    build = build_post,
    file = fm,
  }
  local assoc_kind = nil
  if template then
    assoc_kind = "template_config"
  else
    assoc_kind = "post"
  end
  local post_obj = parse_post(fm.path, format)
  return post_dep, post_obj, assoc_kind
end

function get_template_from_post_obj(
    post_obj: post.Post,
    default_template: string,
    direct: boolean
  ): string?
  local pfm = post_obj.frontmatter
  local result = nil
  if direct then
    if pfm ~= nil and pfm.template ~= nil then
      result = pfm.template
    end
  else
    if pfm ~= nil and pfm.page_template ~= nil then
      result = pfm.page_template
    else
      result = default_template
    end
  end
  if result ~= nil then
    return "./templates/" .. result
  else
    return nil
  end
end

function get_template_from_post(
    depmgr: DependencyManager.DependencyManager,
    post_obj: post.Post
  ): (DependencyManager.Dependency?, post.Post?, string?, string?)
  local default_template = depmgr.config.default_template
  local direct_template = get_template_from_post_obj(post_obj, default_template, true)
  if direct_template ~= nil then
    return nil, nil, direct_template, nil
  else
    local pcl = fsx.find_closest("_index.md", post_obj.path)
    if pcl ~= nil then
      local pclfm = fsx.search_filetree(depmgr.rft, pcl)
      if pclfm ~= nil then
        local d, pco, k = create_post_dep(depmgr, pclfm, "markdown", true)
        if pco ~= nil then
          local fn = get_template_from_post_obj(pco, default_template, false)
          if fn ~= nil then
            return d, pco, fn, k
          end
        end
      end
    end
  end
  return nil, nil, "./templates/" .. default_template, nil
end

function get_template_filename_for_post_dep(
    depmgr: DependencyManager.DependencyManager,
    post_dep: DependencyManager.DependencyOrIdx
  ): (DependencyManager.Dependency?, post.Post?, string?, string?)
  local output = depmgr:find_output(post_dep, "post")
  if output ~= nil then
    return get_template_from_post(depmgr, output)
  end
  return nil, nil, nil, nil
end

function get_template_fm_for_post_dep(
    depmgr: DependencyManager.DependencyManager,
    post_dep: DependencyManager.DependencyOrIdx
  ): (DependencyManager.Dependency?, post.Post?, fsx.FileMetadata?, string?)
  local d, p, template_filename, k = get_template_filename_for_post_dep(depmgr, post_dep)
  if template_filename ~= nil then
    print("Template filename " .. template_filename)
    local tplfm = fsx.search_filetree(depmgr.rft, template_filename)
    return d, p, tplfm, k
  end
  return nil, nil, nil, nil
end

--[[

    mapper.add_dependency_file(dependency_root, parsed_post, "templated_post")
    local relevant_template_path = find_template_for_post(post_obj, post_type)
    if relevant_template_path ~= nil then
      relevant_template_path = "templates/" .. relevant_template_path
      local metadata_obj = fsx.search_filetree(rootft, relevant_template_path)
      if metadata_obj ~= nil then
        mapper.handle_template_relationship(ft, rootft, parsed_post, metadata_obj)
      end
    end
]]--
function post_dependency(filetype: string, format: string): (string, DependencyManager.GraphFormerRule)
  local function handle_template_dependency(
    depmgr: DependencyManager.DependencyManager,
    parent: DependencyManager.DependencyOrIdx,
    sft: fsx.FiletreeOutput,
    f: fsx.FileMetadata
  ): (
      DependencyManager.DependencyOrIdx?,
      DependencyManager.DependencyOrIdx?,
      post.Post?,
      string?
    )
    local post_config_dep, p, tpl_f, k = get_template_fm_for_post_dep(
      depmgr,
      parent
    )
    local template_dependency: DependencyManager.Dependency = {
      build = build_template,
      file = tpl_f,
    }
    return post_config_dep, template_dependency, p, k
  end
  local function graph_former_rule(
    depmgr: DependencyManager.DependencyManager,
    parent: DependencyManager.DependencyOrIdx,
    sft: fsx.FiletreeOutput,
    f: fsx.FileMetadata
  ): ()
    if f.filetype == filetype and f.name ~= "_index.md" then
      local post_dep, post_obj = create_post_dep(depmgr, f, format, false)
      depmgr:add_association(parent, post_dep, "post")
      depmgr:add_output(post_dep, "post", post_obj)
      local post_config_dependency,
        template_dependency,
        tpl_post_obj,
        assoc_kind = handle_template_dependency(depmgr, post_dep, sft, f)

      local intermediate = post_dep
      if post_config_dependency ~= nil and assoc_kind ~= nil then
        depmgr:add_association(intermediate, post_config_dependency, assoc_kind)
        intermediate = post_config_dependency :: DependencyManager.Dependency
        depmgr:add_output(post_config_dependency, "post", tpl_post_obj)
      end
      if template_dependency ~= nil then
        depmgr:add_association(intermediate, template_dependency, "template")
      end
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

  local md_name, md_func = post_dependency("md", "markdown_mmd")
  depmgr:add_gfr(md_name, md_func)
  depmgr:add_root(build_root)
  depmgr:build_graph()
  depmgr:visualize_graph()
  depmgr:build_all()
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
