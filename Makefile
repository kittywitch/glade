mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
root_dir := $(shell dirname $(mkfile_path))
project_dir := $(root_dir)/src
third_party := $(project_dir)/third-party

markdown-fix:
	patch $(third_party)/lua-markdown/markdown.lua -i $(third_party)/markdown.diff -o $(third_party)/markdown.lua
template-fix:
	patch $(third_party)/lua-template/template.lua -i $(third_party)/template.diff -o $(third_party)/template.lua
htmlparser-fix:
	patch $(third_party)/lua-htmlparser/src/htmlparser.lua -i $(third_party)/htmlparser.diff -o $(third_party)/htmlparser.lua
run: markdown-fix template-fix htmlparser-fix
	lune run $(project_dir)
