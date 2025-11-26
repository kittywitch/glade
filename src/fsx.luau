local fs = require("@lune/fs")
local tablex = require("@project/tablex")
local regex = require("@lune/regex")

local fsx = {}

function fsx.get_all_of_type(filetype: string, directory: string): { filename: string }
  local pattern = regex.new(filetype .. "$")
  local files_in_directory: table = {}
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

return fsx
