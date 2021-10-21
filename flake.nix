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
      in
      final: prev:
        {
          nixpkgs-terraform-pkgs = nixpkgs-terraform.legacyPackages.${final.system};

          inherit (final.nixpkgs-terraform-pkgs)
            terraform terraform-providers;

          terraform-with-plugins = final.terraform.withPlugins
            (plugins: lib.attrVals [ "hcloud" ] plugins);
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
      devShell = pkgs.mkShell {
        buildInputs = [
          terraform
          pkgs.nixpkgs-fmt
        ];
      };
    });
}
