--[[
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
]]--
--[[
-- A chain is a source, a process and a sink.
-- You can have only a source, and a sink into some kind of global, like templates
-- however, in this case a chain is for doing file IO with a pipeline process.
]]--
--[[function build_markdown_chain(markdown_source: any)
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
end]]--
--[[
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

end]]--

--[[
local mapper = {}

local posts_store: { [string]: post.Post } = {}
local template_store: { [string]: (...any) -> ...any } = {}
local templated_posts_store: { [string]: string } = {}

local store = {
  posts = posts_store,
  templates =  template_store,
  templated_posts = templated_posts_store,
}

local root_edge_result_mapper: { [string]: (...any) -> ...any } = {
  templated_post = get_templated_post
}

function get_templated_post(lookup: string): string
  return store.templated_posts[lookup]
end

function root_build(edges: { dag.DAGEdge})
  for i, edge in edges do
    if edge.kind ~= nil then
      local mapper_func = edge_kind_mapper[root_edge.kind]
      local content_func = edge_result_mapper[root_edge.kind]
      if mapper_func ~= nil and content_func ~= nil then
        local from_idx = edge.from
        local dep = dependency_map[from_idx]
        local dep_path = dep.file.path
        local mapped_path = mapper_func(site_config, dep_path)
        local mapped_content = content_func(dep_path)
        fsx.produce_file(mapped_path, mapped_content)
      end
    end
  end
end

local dependency_root: RootDependency = {
  build = root_build,
}

table.insert(dependency_map, dependency_root)

type DependencyRule = {
  filetype: string,
}


function parse_post(format: string, path: string): post.Post?
  local post_obj = post.parse(format, path)
  if post_obj ~= nil then
    store.posts[path] = post_obj
  end
  return post_obj
end

function find_template_for_post(post: post.Post, post_type: string): string?
  if post.frontmatter ~= nil and post.frontmatter.template ~= nil then
    return post.frontmatter.template
  else
    local page_config_location = fsx.find_closest("_index.md", post.path)
    if page_config_location ~= nil then
      local page_config_obj = parse_post(post_type, page_config_location)
      if page_config_obj ~= nil
          and page_config_obj.frontmatter ~= nil
          and page_config_obj.frontmatter.template ~= nil then
        return page_config_obj.frontmatter.template
      end
    end

    if site_config.default_template ~= nil then
      return site_config.default_template
    end
  end
  return nil
end

function mapper.handle_template_relationship(ft: fsx.FiletreeOutput, rootft: fsx.FiletreeOutput, file: Dependency, metadata_file: fsx.FileMetadata)
  local metadata_obj: TemplateDependency = {
    file = metadata_file,
    build = template_build,
  }
  mapper.add_dependency_file(metadata_obj, file, "template")
end

function template_build(dependency: Dependency, edges: { DAGEdge })
  local casted_dependency = dependency :: TemplateDependency
  local compiled = compile_template(casted_dependency.file)
  local template_name = casted_dependency.file.name
  store.templates[template_name] = compiled
end

function post_build(dependency: PostDependency, edges: { DAGEdge })
  local template_dependency = nil
  for i, edge in edges do
    if edge.kind == "template" then
      template_dependency = dependency_map[edge.from] :: TemplateDependency
    end
  end
  if template_dependency ~= nil then
    local template_name = template_dependency.file.name
    local templater = store.templates[template_name]
    local context = {
      config = site_config,
    }
    local result = apply_template(templater, dependency.post, context)
    store.templated_posts[dependency.file.path] = result
  end
end

function compile_template(file: fsx.FileMetadata): (...any) -> ...any
  return template.parse(file.path)
end

function apply_template(template: (...any) -> ...any, post: post.Post, context: any): string
  local new_context = {
    post = post,
    context = context,
  }
  return template(new_context)
end

function mapper.handle_post_relationship(ft: fsx.FiletreeOutput, rootft: fsx.FiletreeOutput, file: fsx.FileMetadata, post_type: string)
  local post_obj = parse_post(post_type, file.path)
  if post_obj ~= nil then
    local parsed_post: PostDependency = {
      file = file,
      post = post_obj,
      build = post_build,
    }
    mapper.add_dependency_file(dependency_root, parsed_post, "templated_post")
    local relevant_template_path = find_template_for_post(post_obj, post_type)
    if relevant_template_path ~= nil then
      relevant_template_path = "templates/" .. relevant_template_path
      local metadata_obj = fsx.search_filetree(rootft, relevant_template_path)
      if metadata_obj ~= nil then
        mapper.handle_template_relationship(ft, rootft, parsed_post, metadata_obj)
      end
    end
  end
end

function handle_markdown(ft: fsx.FiletreeOutput, rootft: fsx.FiletreeOutput, file: fsx.FileMetadata)
  if file.filetype == "md" then
    mapper.handle_post_relationship(ft, rootft, file, "markdown_mmd")
  end
end


type Recipes = {
  [string]: (...any) -> ...any
}

local recipes: Recipes = {
  ["handle_markdown"] = handle_markdown,
}


function mapper.build_dependency_graph(ft: fsx.FiletreeOutput, root: fsx.FiletreeOutput)
  print("File location" .. ft.path)
  for subpath, entry in ft.files do
    for rn, recipe in recipes do
      print("Calling recipe " .. rn .. " on " .. entry.path)
      recipe(ft, root, entry)
    end
  end
  for subpath, entry in ft.dirs do
      print("Recursive subcall of build_dependency_graph on " .. subpath)
      mapper.build_dependency_graph(entry, root)
  end
end

local root_edge_kind_mapper: { [string]: (tablex.TableWildcard, string) -> string } = {
  templated_post = content_path_mapper,
}
