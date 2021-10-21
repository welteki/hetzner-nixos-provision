terraform {
  required_providers {
    hcloud = {
      source  = "nixpkgs/hcloud"
      version = "~> 1.26.0"
    }
  }

  ## Prevent unwanted updates
  required_version = "1.0.9" # Use nix-shell or nix develop
}

variable "hc_token" {
  description = "Hetzner Cloud API token"
}

provider "hcloud" {
  token = var.hc_token
}

resource "hcloud_server" "nixos" {
  name   = "nixos-${terraform.workspace}"
  image       = "ubuntu-20.04"
  server_type = "cx11"
  # Install NixOS 20.05
  user_data = file("${path.module}/cloud-config.txt")
}
