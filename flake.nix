{
  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
    tree-sitter-luau-src = {
      url = "github:polychromatist/tree-sitter-luau";
      flake = false;
    };
    tree-sitter-pkg = {
      url = "github:tree-sitter/tree-sitter";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { self, nixpkgs, tree-sitter-luau-src, ... }@inputs: let
    inherit (nixpkgs) lib;
    inherit (lib.attrsets) genAttrs;
    inherit (lib.meta) getExe';
    forAllSystems = genAttrs lib.systems.flakeExposed;
    pkgs' = system: import nixpkgs {
      inherit system;
    };

  in {
    devShells = forAllSystems (system: let
      pkgs = pkgs' system;
      tree-sitter-luau = pkgs.tree-sitter.buildGrammar {
        version = "2025-03-15";
        pname = "tree-sitter-luau-grammar";
        src = tree-sitter-luau-src.outPath;
        language = "luau";
        meta.homepage = "https://github.com/polychromatist/tree-sitter-luau";
      };
      tree-sitter-plugins' = (p: with p; [
        tree-sitter-luau
        tree-sitter-toml
        tree-sitter-json
        tree-sitter-c
        tree-sitter-lua
        tree-sitter-rust
        tree-sitter-bash
        tree-sitter-css
        tree-sitter-go
        tree-sitter-hcl
        tree-sitter-html
        tree-sitter-javascript
        tree-sitter-markdown
        tree-sitter-nix
        tree-sitter-python
        tree-sitter-regex
        tree-sitter-scss
      ]);
      tree-sitter-srcs' = pkgs.linkFarm "sourcies" (map (pkg:
        {
          name = pkg.pname;
          path = pkg.src;
        }
      ) (tree-sitter-plugins' pkgs.tree-sitter-grammars));
      tree-sitter-srcs = tree-sitter-srcs'.overrideAttrs (old: {
        buildCommand = old.buildCommand or "" + ''
          mv $out/tree-sitter-luau-grammar{,.bak}
          cp -rL $out/tree-sitter-luau-grammar{.bak,}
          rm -r $out/tree-sitter-luau-grammar.bak
          chmod +w $out/tree-sitter-luau-grammar{,/tree-sitter.json}

          sed -i -e 's/helix-queries\\\\/helix-queries\//g' $out/tree-sitter-luau-grammar/tree-sitter.json
        '';
      });
      tree-sitter-plugins = pkgs.tree-sitter.withPlugins tree-sitter-plugins';
      in {
        default = pkgs.mkShell {
          TREE_SITTER_LIBDIR = tree-sitter-plugins;
          TREE_SITTER_CONFIG = pkgs.writeText "grammar_config" (builtins.toJSON {
            parser-directories = [ tree-sitter-srcs ];
          });
          shellHook = ''
            cp -f $TREE_SITTER_CONFIG $REPO_ROOT/.treesitter-config.json
          '';
          nativeBuildInputs = with pkgs; [
            gnumake
            grass-sass
            pandoc
            stylua
            luau-lsp
            lune
          ];
          buildInputs = let
            treesitter = inputs.tree-sitter-pkg.packages.${system}.cli;
          in [
            treesitter
          ];
        };
    });
  };
}
