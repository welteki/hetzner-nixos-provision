{
  description = "Flake with some boilerplate";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-21.05";
    nixpkgs-unstable.url = "nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;
  };

  outputs = { self, nixpkgs, utils, ... }@inputs: {
    overlay =
      let
        inherit (inputs) nixpkgs-unstable;
        inherit (nixpkgs) lib;

        tf-module = ./terraform;
      in
      final: prev:
        {
          nixpkgs-unstable-pkgs = nixpkgs-unstable.legacyPackages.${final.system};

          inherit (final.nixpkgs-unstable-pkgs)
            terraform terraform-providers faas-cli buildGoModule;

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

              if [ $TF_BACKEND_conn_str ]; then
                BACKEND_CONFIG=-backend-config="conn_str=$TF_BACKEND_conn_str"
              fi

              ${final.coreutils}/bin/ln -sf ${tf-module}/* $TF_WORKING_DIR
              ${terraform} init $BACKEND_CONFIG \
                && ${terraform} $@
            '';

          of-watchdog = final.buildGoModule rec {
            pname = "of-watchdog";
            version = "0.8.4";
            rev = "bbd2e96214264d6b87cc97745ee9f604776dd80f";

            src = final.fetchFromGitHub {
              owner = "openfaas";
              repo = "of-watchdog";
              rev = version;
              sha256 = "19kg0kf0wf04yapcnbyi58qlxrf1wzlckyxvnnyvpym44zvm7m6d";
            };

            vendorSha256 = null;

            CGO_ENABLED = 0;

            subPackages = [ "." ];

            ldflags = [
              "-s"
              "-w"
              "-X main.GitCommit=${rev}"
              "-X main.Version=${version}"
            ];
          };

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

          provision-fn =
            let
              provision = final.writeShellScriptBin "terraform-provision" ''
                export TF_BACKEND_conn_str=''${TF_BACKEND_conn_str:=$(${final.coreutils}/bin/cat /var/openfaas/secrets/tf_backend_conn_str)}
                export TF_VAR_hc_token="''${TF_VAR_hc_token:-$(${final.coreutils}/bin/cat /var/openfaas/secrets/tf_var_hc_token)}"

                ${final.terraform-wrapped}/bin/terraform workspace new $Http_Workspace \
                  && TF_WORKSPACE=$Http_Workspace ${final.terraform-wrapped}/bin/terraform apply -input=false -auto-approve=true
              '';
            in
            final.dockerTools.buildImage {
              name = "hcloud-nixos-provision";
              tag = "latest";

              contents = [
                final.cacert
              ];

              extraCommands = ''
                # required to run terraform
                mkdir -p tmp

                mkdir -p var/openfaas/secrets
              '';

              config = {
                Cmd = [ "${final.of-watchdog}/bin/of-watchdog" ];
                Env = [
                  "fprocess=${provision}/bin/terraform-provision"

                  "exec_timeout=60s"
                  "write_timeout=65s"
                  "read_timeout=65s"

                  "TF_IN_AUTOMATION=true"
                  "TF_VAR_hc_token"
                  "TF_BACKEND_conn_str"
                ];
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
        inherit (pkgs) terraform-wrapped provision-image of-watchdog provision-fn;
      };

      devShell = pkgs.mkShell {
        buildInputs = [
          terraform
          pkgs.faas-cli
          pkgs.nixpkgs-fmt
        ];
      };
    });
}
