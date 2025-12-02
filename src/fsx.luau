local fs = require("@lune/fs")
local tablex = require("@project/tablex")
local regex = require("@lune/regex")

local option = require("@rustyluau/option")

type Option<T> = option.Option<T>
local Option, Some, None = option.Option, option.Some, option.None

local fsx = {}

function fsx.get_all_of_type(filetype: string, directory: string): { filename: string }
  local pattern = regex.new(filetype .. "$")
  local files_in_directory: tablex.TableWildcard = {}
  for _, unaffixedEntry in fs.readDir(directory) do
    local entry: string = directory .. "/" .. unaffixedEntry

    if fs.isFile(entry) and pattern:isMatch(entry) then
      table.insert(files_in_directory, entry)
    elseif fs.isDir(entry) then
      local files_in_subdirectory = fsx.get_all_of_type(filetype, entry)
      tablex.combine(files_in_directory, files_in_subdirectory)
    end
  end
  return files_in_directory
end

--[[
-- i thought about just allowing regular expression based filtering but i
-- realised it would be far cuter to allow for turing completeness and freedom
-- of filtering the filetree, so you get this.
]]--
export type FiletreeFilter = (string) -> boolean

export type FiletreeRecipe = (FiletreeOutput) -> ()

export type FiletreeConfig = {
  filters: { FiletreeFilter },
}

export type FileCommon = {
  path: Option<string>,
  metadata: fs.Metadata,
}

export type FileMetadata = {
  name: string,
  filetype: Option<string>,
  basename: string,
} & FileCommon

export type FiletreeOutput = {
  dirs: {
    [string]: FiletreeOutput
  },
  files: {
    [string]: FileMetadata
  },
} & FileCommon

function fsx.get_by_path(ft: FiletreeOutput, path: string): Option<FileMetadata>
  print("fsx.get_by_path: Called on " .. path)
  local check_path = string.gsub(path, "\.\/", "", 1)
  local split_path = string.split(check_path, "/")
  local filename = table.remove(split_path, #split_path)
  local context = ft
  for i, subpath in split_path do
    context = context.dirs[subpath]
  end
  if filename ~= nil and context.files[filename] ~= nil then
      return Some(context.files[filename])
  end
  return None()
end

function fsx.build_filetree(directory: string, config: FiletreeConfig): FiletreeOutput
  local tree: FiletreeOutput = {
    path = Some(directory),
    metadata = fs.metadata(directory),
    files = {},
    dirs = {},
  }
  for _, entry in fs.readDir(directory) do
    -- ensure that directories actually terminate with a / on the recursive call
    if string.sub(directory, -1, -1) ~= "/" then
      directory = directory .. "/"
    end
    local path = directory .. entry
    local add_to_files = true
    -- avoid ./ causing issues for a regex filter that does \. (or \\.)
    local check_path = string.gsub(path, "\.\/", "", 1)
    for _, filter in config.filters do
      if not filter(check_path) then
        add_to_files = false
        break
      end
    end
    if add_to_files then
      if fs.isFile(path) then
        local split_filename = string.split(entry, ".")
        local basename = entry
        local filetype = None()
        if #split_filename > 1 then
          basename = split_filename[1]
          filetype = Some(split_filename[2])
        end
        local metadata: FileMetadata = {
          path = Some(path),
          name = entry,
          basename = basename,
          filetype = filetype,
          metadata = fs.metadata(path),
        }
        tree.files[entry] = metadata
      elseif fs.isDir(path) then
        local files_in_subdirectory = fsx.build_filetree(path, config)
        tree.dirs[entry] = files_in_subdirectory
      end
    end
  end
  return tree
end

function fsx.basedir(path: string): string
  local split_path = string.split(path, "/")
  table.remove(split_path, #split_path)
  local new_path = table.concat(split_path, "/")
  return new_path
end

function fsx.produce_file(path: string, content: string): ()
  print("Asked to produce file at " .. path)
  local base_dir = fsx.basedir(path)
  if not fs.isDir(base_dir) then
    fs.writeDir(base_dir)
  end
  if fs.isFile(path) then
    fs.removeFile(path)
  end
  fs.writeFile(path, content)
end

function fsx.find_closest(needle: string, haystack: string): Option<string>
  local basedir = fsx.basedir(haystack)
  if basedir == "./" or basedir == "." then
    return None()
  end
  local location = basedir .. "/" .. needle
  if fs.isFile(location) then
    print("Needle found at " .. location .. "!")
    return Some(location)
  else
    print("Recursing for " .. needle .. " in " .. basedir)
    return fsx.find_closest(needle, basedir)
  end
end

return fsx
