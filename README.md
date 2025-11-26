# glade

A half-baked work in progress static site generator written in [Lune](https://lune-org.github.io/docs/) and thus [Luau](https://luau.org/).

[Current to-dos](./TODO.md)

## Usage

```
# An .envrc is provided alongside the project and the project uses a Nix flake
direnv allow
# To run the project once direnv has loaded the environment (this will also
# automatically patch dependencies to function properly)
make run
```

## Ethos

* Use Nix where possible to avoid convolution of the build process
* Use an uncomplicated environment (in my mind, Lune+Luau meets this need)
* Keep things simple, modifiable: no real boundaries between code and data

## Dependencies

Some partially vendored and patched in-tree for Lune/Luau compatibility.

### Lua/Luau
* [dannote/lua-template](https://github.com/dannote/lua-template) for templating
* [mpeterv/markdown](https://github.com/mpeterv/markdown) for markdown
* [msva/lua-htmlparser](https://github.com/msva/lua-htmlparser) for parsing HTML output

### External programs
* [tree-sitter](https://github.com/tree-sitter/tree-sitter/tree/master/crates/cli) for syntax highlighting
