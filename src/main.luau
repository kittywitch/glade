local fs = require("@lune/fs")
local serde = require("@lune/serde")
local post = require("@project/post");
local template = require("@project/template");
local fsx = require("@project/fsx");
local tablex = require("@project/tablex");
local regex = require("@lune/regex")

local main = {}

function load_site_config()
  print("Loading site config")
  local config = serde.decode("toml", fs.readFile("./config.toml"))
  print("Site config loaded")
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

local function result_path_modifier(config: tablex.TableWildcard, path: string)
  local result = config.result_dir .. "/"
  local moved_dir = string.gsub(path, "content/", config.result_dir .. "/")
  local refiletyped = string.gsub(moved_dir, "md", "html")
  return refiletyped
end

type SourceResult = { output: any, context: any, path: string }?

local templates: { [string]: (...any) -> ...any } = {}
local markdown_contexts: { [string]: any } = {}

function build_template_source(): (...any) -> ...any

  local function result_path_modifier(path: string)
    local removed_dir = string.gsub(path, "./templates/", "")
    return removed_dir
  end
  function template_source(fto: fsx.FileMetadata): SourceResult

      if fto.metadata.kind == "file" and fto.filetype == "tpl" then
        local template_result = template.parse(fto.path)
        local path = result_path_modifier(fto.path)
        templates[path] = template_result
        return {
          output = template_result,
          path = path,
        }
      end
      return nil
  end
  return template_source
end

function build_markdown_source(config: tablex.TableWildcard): (...any) -> ...any
  local function result_path_modifier(path: string)
    local result = config.result_dir .. "/"
    local moved_dir = string.gsub(path, "content/", config.result_dir .. "/")
    local refiletyped = string.gsub(moved_dir, "md", "html")
    return refiletyped
  end

  local configuration_path = regex.new("_index.md")

  local function markdown_source(fto: fsx.FileMetadata): SourceResult
    -- Avoid handling the configuration until it is needed so we can store it separately
    if configuration_path:isMatch(fto.path) then
      return nil
    end
    if fto.metadata.kind == "file" and fto.filetype == "md" then
      -- Ensure that the next step has a context to draw from when it comes to the actual template system
      -- actually process the file
      local config_location = fsx.find_closest("_index.md", fto.path)
      if config_location ~= nil and markdown_contexts[config_location] == nil and fs.isFile(config_location) then
        local context = post.parse("markdown_mmd", config_location)
        if context ~= nil then
          markdown_contexts[config_location] = context.frontmatter
        end
      end
      local result_path = result_path_modifier(fto.path)
      local post = post.parse("markdown_mmd", fto.path)
      --print(markdown_contexts)
      if post ~= nil and post.html ~= nil then
        --print("Result path: " .. result_path)
        return {
          output = post,
          context = config_location,
          path = result_path,
        }
      end
    end
    return nil
  end
  return markdown_source
end

function template_process(result: SourceResult): SourceResult?
  if result ~= nil then
    if result.context ~= nil then
      local template_index = markdown_contexts[result.context].template
      print(result.context)
      print(markdown_contexts)
      print(templates)
      local template_function = templates[template_index]
      print("Calling for " .. result.path)
      result.output = template_function(result.output.html, {})
    else
      result.output = result.output.html
    end
    return result
  end
  return nil
end

function file_sink(result: SourceResult)
    if result ~= nil then
      local output: string = result.output
      print("File sink requested to produce " .. result.path)
      fsx.produce_file(result.path, output)
    end
end

--[[
-- A chain is a source, a process and a sink.
-- You can have only a source, and a sink into some kind of global, like templates
-- however, in this case a chain is for doing file IO with a pipeline process.
]]--
function build_markdown_chain(markdown_source: any)
  local function markdown_chain(ft: fsx.FileMetadata)
    local source = markdown_source(ft)
    if source == nil then
      return
    end
    local process = template_process(source)
    if process == nil then
      return
    end
    file_sink(process)
  end
  return markdown_chain
end

function apply_recipes(ft: fsx.FiletreeOutput, recipes: { [string]: (...any) -> ...any })
  print("File location" .. ft.path)
  for subpath, entry in ft.files do
    for rn, recipe in recipes do
      print("Calling recipe " .. rn .. " on " .. entry.path)
      recipe(entry)
    end
  end
  for subpath, entry in ft.dirs do
      print("Recursive subcall of apply_recipes on " .. subpath)
      apply_recipes(entry, recipes)
  end

end

--[[
-- TODO: Move to DAG for the actual way dependencies are handled
-- for example, if configuration is required, add function for fetching the
-- configuration or checking for it to the graph, then always add a function for
-- continuation of the markdown parsing task. If templating is required,
-- add the continuation of the templating task to the graph. Iterate over the graph
-- while consuming the filesystem, piece by piece to resolve dependencies.
--
-- For any filesystem entry task that succeeds, append immediately after that task
-- (at the front of the queue), more tasks for the actual dependencies and
-- processing / chains required for the result.
]]--
function main.call()
  local config = load_site_config()
  --local _posts = post.handle_all()
  --local _templates = template.handle_all(config)
  local tree_filter = build_filter()
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
  --print(markdown_contexts)
end

return main
