mkfile_path := $(abspath $(lastword $(MAKEFILE_LIST)))
root_dir := $(shell dirname $(mkfile_path))
project_dir := $(root_dir)/src
third_party := $(project_dir)/third-party

template-fix:
	patch $(third_party)/lua-template/template.lua -i $(third_party)/template.diff -o $(third_party)/template.lua
run: template-fix
	lune run $(project_dir)
