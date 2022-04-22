{
  description = "CMark wrapper for Lean";

  inputs = {
    lean = {
      url = "github:leanprover/lean4";
    };
    nixpkgs.url = "github:nixos/nixpkgs/nixos-21.11";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, lean, flake-utils, nixpkgs }:
    let
      supportedSystems = [
        "aarch64-linux"
        "aarch64-darwin"
        "i686-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      inherit (flake-utils) lib;
    in
    lib.eachSystem supportedSystems (system:
      let
        leanPkgs = lean.packages.${system};
        pkgs = nixpkgs.legacyPackages.${system};
        lib = nixpkgs.lib // (import ./nix/lib.nix { inherit (nixpkgs) lib; });
        inherit (lib) concatStringsSep makeOverridable;
        buildCLib = import ./nix/buildCLib.nix { inherit nixpkgs system lib; };
        includes = [
          "${./wrapper}"
          "${./cmark}"
          "${leanPkgs.lean-bin-tools-unwrapped}/include"
        ];
        INCLUDE_PATH = concatStringsSep ":" includes;
        hasPrefix =
          # Prefix to check for
          prefix:
          # Input string
          content:
          let
            lenPrefix = builtins.stringLength prefix;
          in
          prefix == builtins.substring 0 lenPrefix content;
        cmarkName = "cmark";
        cmark-c = buildCLib {
          updateCCOptions = d: d ++ (map (i: "-I${i}") includes);
          name = cmarkName;
          sourceFiles = [ "cmark/*.c" ];
          src = builtins.filterSource
            (path: type: hasPrefix (toString ./. + "/cmark") path) ./.;
          extraDrvArgs = {
            linkName = cmarkName;
          };
        };
        cmark-c-debug = cmark-c.override {
          debug = true;
          updateCCOptions = d: d ++ (map (i: "-I${i}") includes) ++ [ "-O0" ];
        };
        linkName = "lean-cmark-bindings";
        c-shim = buildCLib {
          updateCCOptions = d: d ++ (map (i: "-I${i}") includes);
          name = linkName;
          sourceFiles = [ "wrapper/*.c" ];
          src = builtins.filterSource
            (path: type: hasPrefix (toString ./. + "/wrapper") path) ./.;
          extraDrvArgs = {
            inherit linkName;
          };
        };
        c-shim-debug = c-shim.override {
          debug = true;
          updateCCOptions = d: d ++ (map (i: "-I${i}") includes) ++ [ "-O0" ];
        };
        name = "CMark";  # must match the name of the top-level .lean file
        project = leanPkgs.buildLeanPackage {
          inherit name;
          nativeSharedLibs = [ cmark-c c-shim ];
          # Where the lean files are located
          src = ./src;
        };
        main = leanPkgs.buildLeanPackage {
          name = "Main";
          deps = [ project ];
          # Where the lean files are located
          src = ./src;
        };
        test = leanPkgs.buildLeanPackage {
          name = "Tests";
          deps = [ project ];
          # Where the lean files are located
          src = ./test;
        };
        withGdb = bin: pkgs.writeShellScriptBin "${bin.name}-with-gdb" "${pkgs.gdb}/bin/gdb ${bin}/bin/${bin.name}";
      in
      {
        inherit project test;
        packages = project // {
          ${name} = project.executable;
          test = test.executable;
          inherit c-shim cmark-c c-shim-debug cmark-c-debug;
          debug-test = (test.overrideArgs {
            debug = true;
            deps =
            [ (project.override {
                nativeSharedLibs = [ cmark-c-debug c-shim-debug ];
              })
            ];
          }).executable // { allowSubstitutes = false; };
          gdb-test = withGdb self.packages.${system}.debug-test;
        };

        defaultPackage = self.packages.${system}.${name};
        devShell = pkgs.mkShell {
          inputsFrom = [ project.executable ];
          buildInputs = with pkgs; [
            leanPkgs.lean-dev
          ];
          LEAN_PATH = "./src:./test";
          LEAN_SRC_PATH = "./src:./test";
        };
      });
}
