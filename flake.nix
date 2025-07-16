{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    self.submodules = true;
  };
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        nativeBuildInputs = [
          pkgs.cmake
          pkgs.python3
          pkgs.python3Packages.libclang
          pkgs.shader-slang
        ];
        buildInputs = [
          pkgs.SDL2
          pkgs.vulkan-headers
          pkgs.vulkan-loader
        ];
        CPATH = "${pkgs.glibc.dev}/include";
      in
      {
        defaultPackage = pkgs.stdenv.mkDerivation {
          name = "slang-simple-vulkan";
          src = ./.;
          strictDeps = true;
          inherit nativeBuildInputs buildInputs CPATH;
          installPhase = ''
            mkdir -p $out/bin
            cp *.spv demo $out/bin/
          '';
        };
        devShell = pkgs.mkShell {
          inherit buildInputs CPATH;
          nativeBuildInputs = nativeBuildInputs ++ [
            pkgs.clang-tools
            pkgs.nixfmt-rfc-style
          ];
        };
      }
    );
}
