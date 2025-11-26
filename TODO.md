# To-dos

## Spring cleaning

- [ ] Replace impromptu wildcard table type usage with tablex.TableWildcard

## SSG Core

- [x] Turn markdown posts into HTML
- [x] Generate ToC from post HTML
- [x] Generate LUA template, run with context
    - HTML escaping for free
- [ ] Filesystem management
    - [ ] Migrate to generating the tree from working directory once
    - [ ] Employ a system of rules-based function applicators to produce desired output
    - [ ] Provide route configuration
- [ ] Read post directory config from `_index.md`, etc.
- [ ] Marry template and post system for context.
- [ ] RSS feed generation.
- [ ] Image optimization, thumbnailing and generation.
- [ ] Metadata
    - [ ] [Open Graph support](https://ogp.me/)
    - [ ] Description, language, copyright, tags, subject, ...
- [ ] Use `select_headings` to produce table of contents.
- [ ] Break up current `for` based generation to be capable of generating single post outputs.

## Fancy

- [ ] Directed acyclic graph based dependency resolution for build process
- [ ] Parallelize build steps using https://lune-org.github.io/docs/api-reference/task/
- [ ] Web server (https://lune-org.github.io/docs/api-reference/net/#serve)
- [ ] Hot reload either using filesystem watchers (made using https://lune-org.github.io/docs/api-reference/task/ and fs.metadata), `watchexec` or such.
- [ ] Syntax highlighting
    - [x] Set up environment for tree-sitter
    - [ ] Detect installed languages from tree-sitter with `tree-sitter dump-languages` and then within glade parse that into a list of known potential strings that a code block may start with, such that when we see those at the start of the content of a `<code><pre>` we can in fact call out to tree-sitter as needed and replace the internal content.
    - [ ] Figure out consistent `tree-sitter highlight` CSS styling once embedded via extraction of the code block(s) or table from the output.
    - [ ] Provide `tree-sitter` config generation that allows for theme selection.
    - [ ] Attach `tree-sitter --highlight` to the system.

## Contemplate / exploratory

- [ ] Figure out actual end-goal build pipeline
    - template compilation
    - post generation
    - context for template generation
    - additional optional pipeline steps(?)
        - syntax highlighting
        - image optimization / thumbnailing / generation
    - file I/O & websocket(?)-based reload command to clients
- [ ] Elegant pipeline extensibility
- [ ] Document format extension via a pandoc-based pipeline
    - Could replace the existing lua markdown based conversion to HTML

## To watch

- [ ] Remove patch when https://github.com/polychromatist/tree-sitter-luau/issues/7 changes.
