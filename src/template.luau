local tp_template = require("@project/third-party/template");
local fs = require("@lune/fs")
local fsx = require("@project/fsx")

local template = {}

function template.handle_all(config: { [any]: any }): ()
  local template_files: { string } = fsx.get_all_of_type("tpl", "./templates")
  local templates = {}
  local context = {
    config = config
  }

  print("Starting template handler")
  for i: number, file in template_files do
    print("File " .. i .. ": " .. file)
    local _template = template.parse(file, context)
    table.insert(templates, template)
  end
  print("Template handler job finished")

  return templates
end

function template.parse(path: string, context: { [any]: any }): (...any) -> ...any
  local file_content = fs.readFile(path)
  local tpl = tp_template.parse(file_content, false)
  print(tpl)
  local templated = tp_template.compile(file_content)
  --[[
  print("Template context:")
  print(context)
  print("Template output:")
  tp_template.print(templated, context, false)
  ]]--
  return templated
end

return template
