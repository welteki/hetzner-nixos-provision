{
  description = "Flake with some boilerplate";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-21.05";
    nixpkgs-terraform.url = "nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;
  };

  outputs = { self, nixpkgs, utils, ... }@inputs: {
    overlay =
      let
        inherit (inputs) nixpkgs-terraform;
        inherit (nixpkgs) lib;

        tf-module = ./terraform;
      in
      final: prev:
        {
          nixpkgs-terraform-pkgs = nixpkgs-terraform.legacyPackages.${final.system};

          inherit (final.nixpkgs-terraform-pkgs)
            terraform terraform-providers;

          terraform-with-plugins = final.terraform.withPlugins
            (plugins: lib.attrVals [ "hcloud" ] plugins);

          terraform-wrapped = final.writeShellScriptBin "terraform" ''
            TF_DATA_DIR="$PWD/.terraform" ${final.terraform-with-plugins}/bin/terraform -chdir=${tf-module} $@
          '';
        };

  } // utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ self.overlay ];
      };

      terraform = pkgs.terraform-with-plugins;
    in
    {
      packages = {
        inherit (pkgs) terraform-wrapped;
      };

      devShell = pkgs.mkShell {
        buildInputs = [
          terraform
          pkgs.nixpkgs-fmt
        ];
      };
    });
}
