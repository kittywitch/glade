local fs = require("@lune/fs")
local regex = require("@lune/regex")
local serde = require("@lune/serde")
local dateTime = require("@lune/datetime")
local process = require("@lune/process")
local tablex = require("@project/tablex");
local fsx = require("@project/fsx");

local option = require("@rustyluau/option")
local Option = option.Option
type Option<T> = option.Option<T>
local None = option.None
local Some = option.Some

local post = {}

export type Post = {
  frontmatter: {[any]: any},
  body: Option<string>,
  html: Option<string>,
  path: string,
}


function post.parse_metadata(path: string, content: string): Option<Post>
  --[[
  -- Modified from https://github.com/getzola/zola/blob/a1a62bad0bb29c2c70251bd2b48f942f4c1dbd2b/components/content/src/front_matter/split.rs#L11-L21
  -- Difference is, remainder of file is no longer non-capturing capture group
  ]]--
  local frontmatter_patterns: { [serde.EncodeDecodeFormat]: regex.Regex } = {
    toml = regex.new("^[[:space:]]*\\+\\+\\+(\\r?\\n(?s).*?(?-s))\\+\\+\\+[[:space:]]*($|(?:\\r?\\n((?s).*(?-s))$))");
    yaml = regex.new("^[[:space:]]*---(\\r?\\n(?s).*?(?-s))---[[:space:]]*($|(?:\\r?\\n((?s).*(?-s))$))");
  }
  -- TODO: handle page without frontmatter
  local post: Option<Post> = None()
  for frontmatter_type: serde.EncodeDecodeFormat, frontmatter_pattern in frontmatter_patterns do
    if frontmatter_pattern:isMatch(content) then
      local frontmatter_captures: regex.RegexCaptures? = frontmatter_pattern:captures(content)
      if frontmatter_captures == nil then
        return post
      end
      local frontmatter_capture: any = frontmatter_captures:get(1)
      local frontmatter = serde.decode(frontmatter_type, frontmatter_capture.text)

      local body_capture = frontmatter_captures:get(2)
      local body = nil
      if body_capture ~= nil then
        body = body_capture.text
      end

      --[[
      -- Handle date types from https://github.com/getzola/zola/blob/a1a62bad0bb29c2c70251bd2b48f942f4c1dbd2b/components/content/src/front_matter/page.rs#L79
      -- YAML: https://yaml.org/type/timestamp.html
      -- TOML: https://toml.io/en/v1.0.0#offset-date-time
      ]]--
      if frontmatter.date ~= nil then
        local ymd_pattern = regex.new("^(\\d{4})-(0[1-9]|1[0-2]|[1-9])-([1-9]|0[1-9]|[1-2]\\d|3[0-1])$")
        local internal_date = nil
        -- Lune's serde library makes TOML datetimes *weird*.
        if frontmatter_type == "toml" then
          internal_date = frontmatter.date["$__toml_private_datetime"]
        else
          internal_date = frontmatter.date
        end

        -- Can error, instead of using regex isMatch against an Rfc3339 compliant pattern, just check for error
        local status, data = pcall(dateTime.fromRfc3339, internal_date)
        if status then
          frontmatter.date = data
        else
          -- Parse it out manually with a yyyy-mm-dd pattern
          if ymd_pattern:isMatch(internal_date) then
            -- return zero if the capture fails, which it shouldn't
            local function rzin_ton_get(capture: regex.RegexCaptures, num: number): number
              local cap = capture:get(num)
              if cap ~= nil then
                local str = cap.text
                local numy = tonumber(str)
                if numy ~= nil then
                  return numy
                else
                  return 0
                end
              else
                return 0
              end
            end

            local date_captures: regex.RegexCaptures? = ymd_pattern:captures(internal_date)
            --[[
            -- They make me provide a HH:MM:SS.ms, my critiques so far are... if I don't have more accuracy than
            -- "it was this day when this happened", don't make me provide the remainder with a sense of fake accuracy?
            -- Like, does one UTC this? Does one localtime it? Who knows.
            ]]--
            if date_captures ~= nil and #date_captures == 4 then
              local dt_args: dateTime.DateTimeValueArguments = {
                year = rzin_ton_get(date_captures, 1),
                month = rzin_ton_get(date_captures, 2),
                day = rzin_ton_get(date_captures, 3),
                hour = 0,
                minute = 0,
                second = 0,
                millisecond = 0,
              }
              local date = dateTime.fromLocalTime(dt_args)
              frontmatter.date = date
            end
          end
        end
      else
        local file_metadata = fs.metadata(path)
        frontmatter["date"] = file_metadata.createdAt
      end
      post = Some({
        frontmatter = frontmatter,
        body = Some(body),
        html = None(),
        path = path,
      })
    end
  end
  return post
end

function post.handle_pandoc(input: string, from: string, to: string, toc: boolean, wrap: boolean): Option<string>
  local pandoc_args = {
    "-s",
    "-f",
    from,
    "-t",
    to,
    "--table-of-contents="..tostring(toc),
    "--template=pandoc-template.html",
  };
  if not wrap then
    table.insert(pandoc_args, "--wrap=none")
  end
  local exec_opts: process.ExecOptions = {
    cwd = process.env["REPO_ROOT"] .. "/src",
    stdio = {
      stdin = input,
    },
  }
  local pandoc_result = process.exec("pandoc", pandoc_args, exec_opts)
  --print(pandoc_result)
  if pandoc_result.ok then
    return Some(pandoc_result.stdout)
  else
    return None()
  end
end

type Heading = {
  content: string,
  children: HeadingList,
}

type HeadingList = {
  [string]: Heading
}


-- TODO: remove
function _select_headings(elem): HeadingList
  local headings = {}
  for i=1,6 do
    local level = elem("h"..tostring(i))
    for _, subelem in level do
      local index = subelem.index
      table.insert(headings, index, {
        content = subelem:getcontent(),
        level = i,
      })
    end
  end
  headings = tablex.sort_bullshit(headings)

  local headings_tree = {}
  local current_scope = {}
  local last_level = 0
  for _, subelem in ipairs(headings) do
    if subelem.level > last_level then
      table.insert(current_scope, subelem.content)
      last_level = subelem.level
    elseif subelem.level <= last_level then
      current_scope = tablex.get_n_minus(current_scope, 1)
      table.insert(current_scope, subelem.content)
      last_level = subelem.level
    end
    local subpath = tablex.get_fake_key(headings_tree, current_scope)
    if subpath.children ~= nil then
      subpath = subpath.children
    end
    table.insert(subpath, {
      content = subelem.content,
      children = {},
    })
  end
  return headings_tree
end

function post.parse(format: string, path: string): Option<Post>
  local file_content = fs.readFile(path)
  local parsed_post = post.parse_metadata(path, file_content)
  return parsed_post:map(function(ppost)
    local body = ppost.body
    if body:isSome() then
      ppost.html = post.handle_pandoc(body:unwrap(), format, "html", true, false)
    end
    return ppost
  end)
end

function post.handle_all()
  local body_files: {string} = fsx.get_all_of_type("md", "./content")
  local posts = {}

  print("Starting post handler")
  for i: number, file: string in body_files do
    print("File " .. i .. ": " .. file)
    local namespace = string.split(file, "/")
    -- remove . and content
    table.remove(namespace, 1)
    table.remove(namespace, 1)

    --[[
    -- scope our purview to how far we are into creating the nested
    -- namespace
    ]]--
    local purview: { [any]: any } = posts
    for _, section in namespace do
      -- if our nested folder isn't within the tree, make it
      if purview[section] == nil then
        purview[section] = {}
      end
      purview = purview[section]
    end
    local parsed_post = post.parse("markdown", file)
    if parsed_post ~= nil then
      table.insert(purview, parsed_post)
    else
      print("File " .. i .. " " .. file .. " failed to parse correctly.")
    end
  end
  print("Post handler job finished")
  print("Stripped structure:")
  local stripped = tablex.strip_values(posts)
  print(stripped)
  print("Stripped structure end")

  return posts
end

return post
