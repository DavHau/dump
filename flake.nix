{
  description = "Mono repo of DavHau";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-22.11";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    drv-parts.url = "github:DavHau/drv-parts";
    drv-parts.inputs.nixpkgs.follows = "nixpkgs";
    drv-parts.inputs.flake-parts.follows = "flake-parts";

    # hugo theme
    hugo-theme.url = "github:luizdepra/hugo-coder";
    hugo-theme.flake = false;

    # pull readmes for the project section of the blog
    blog_project_dream2nix.url = "github:nix-community/dream2nix";
    blog_project_dream2nix.flake = false;
    blog_project_nix-portable.url = "github:davhau/nix-portable";
    blog_project_nix-portable.flake = false;
    blog_project_mach-nix.url = "github:davhau/mach-nix";
    blog_project_mach-nix.flake = false;
    blog_project_drv-parts.url = "github:davhau/drv-parts";
    blog_project_drv-parts.flake = false;
    blog_project_systemd2nix.url = "github:davhau/systemd2nix";
    blog_project_systemd2nix.flake = false;
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {

      systems = [
        "x86_64-linux"
      ];

      imports = [
        ./nix/modules/flake-parts/all-modules.nix
      ];
    };
}
