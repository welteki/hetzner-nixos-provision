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

          terraform-wrapped =
            let
              terraform = "TF_DATA_DIR=\${TF_DATA_DIR:-$PWD/.terraform} ${final.terraform-with-plugins}/bin/terraform -chdir=$TF_WORKING_DIR";
            in
            final.writeShellScriptBin "terraform" ''
              TF_WORKING_DIR=$(${final.coreutils}/bin/mktemp -tp /tmp -d terraform-run.XXXXX)

              # Cleanup working dir on shell exit
              trap '${final.coreutils}/bin/rm -rf -- "$TF_WORKING_DIR"' EXIT

              ${final.coreutils}/bin/ln -sf ${tf-module}/* $TF_WORKING_DIR
              ${terraform} init \
               && ${terraform} $@
            '';

          provision-image = final.dockerTools.buildImage {
            name = "hcloud-provision";
            tag = "latest";

            contents = [
              final.bashInteractive
              final.terraform-wrapped
              final.cacert
            ];

            extraCommands = ''
              # required to run terraform
              mkdir -p tmp
            '';

            config = {
              Cmd = [ "bash" ];
            };
          };
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
        inherit (pkgs) terraform-wrapped provision-image;
      };

      devShell = pkgs.mkShell {
        buildInputs = [
          terraform
          pkgs.nixpkgs-fmt
        ];
      };
    });
}
