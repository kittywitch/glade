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

function build_markdown_recipe(config: tablex.TableWildcard): (...any) -> ...any
  local function result_path_modifier(path: string)
    local result = config.result_dir .. "/"
    local moved_dir = string.gsub(path, "content/", config.result_dir .. "/")
    local refiletyped = string.gsub(moved_dir, "md", "html")
    return refiletyped
  end

  local function markdown_recipe(fto: fsx.FileMetadata)
    if fto.metadata.kind == "file" and fto.filetype == "md" then
        local result_path = result_path_modifier(fto.path)
        local post = post.parse("markdown", fto.path)
        if post ~= nil and post.html ~= nil then
          print("Result path: " .. result_path)
          fsx.produce_file(result_path, post.html)
        end
    end
  end
  return markdown_recipe
end

function apply_recipes(ft: fsx.FiletreeOutput, recipes: {(...any) -> ...any})
  print("File location" .. ft.path)
  for subpath, entry in ft.files do
    for i, recipe in recipes do
      print("Calling recipe " .. i .. " on " .. entry.path)
      recipe(entry)
    end
  end
  for subpath, entry in ft.dirs do
      print("Recursive subcall of apply_recipes on " .. subpath)
      apply_recipes(entry, recipes)
  end

end

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
  local recipes = {}
  local unbuilt_recipes = {
    build_markdown_recipe
  }
  for _, unbuilt_recipe in unbuilt_recipes do
    table.insert(recipes, unbuilt_recipe(config))
  end
  local filetree: fsx.FiletreeOutput = fsx.build_filetree("./", filetree_config)
  apply_recipes(filetree, recipes)
end

return main
