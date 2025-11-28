local fs = require("@lune/fs")
local tablex = require("@project/tablex")
local regex = require("@lune/regex")

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

--[[
-- the use of _ suffixes here is specifically for the purpose of avoiding
-- any potential collisions with files called "metadata" or "path". i don't
-- really know why you would name them that, but there we go, y'know?
--
-- this applies to both FileMetadata and FiletreeOutput.
--
-- by the way, I tried using table type combination with & over a "FileCommon"
-- where it contained _metadata and _path and *it does work but only for
-- FileMetadata for FiletreeOutput, the only way providing the _ prefixed keys
-- works is by providing them before the [string] in the same table definition
-- so that's kind of sad, would've been cute to combine both definitions that
-- way.
]]--

export type FileMetadata = {
  name: string,
  filetype: string,
  basename: string,
  metadata: fs.Metadata,
  path: string,
}

export type FiletreeOutput = {
  metadata: fs.Metadata,
  path: string,
  dirs: {
    [string]: FiletreeOutput
  },
  files: {
    [string]: FileMetadata
  },
}

function fsx.build_filetree(directory: string, config: FiletreeConfig): FiletreeOutput
  local tree: FiletreeOutput = {
    path = directory,
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
        local filetype = nil
        if #split_filename > 1 then
          basename = split_filename[1]
          filetype = split_filename[2]
        end
        local metadata: FileMetadata = {
          path = path,
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
  local base_dir = fsx.basedir(path)
  if not fs.isDir(base_dir) then
    fs.writeDir(base_dir)
  end
  if fs.isFile(path) then
    fs.removeFile(path)
  end
  fs.writeFile(path, content)
end

return fsx
