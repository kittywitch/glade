local fs = require("@lune/fs")
local serde = require("@lune/serde")
local post = require("@project/post");
local template = require("@project/template");

local main = {}

function load_site_config()
  print("Loading site config")
  local config = serde.decode("toml", fs.readFile("./config.toml"))
  print("Site config loaded")
  return config
end

function main.call()
  local config = load_site_config()
  local _posts = post.handle_all()
  local _templates = template.handle_all(config)
end

return main
