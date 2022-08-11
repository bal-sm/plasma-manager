{
  description = "Manage KDE Plasma with Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.05";
    nixpkgs_unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    home-manager.url = "github:nix-community/home-manager/release-22.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    kconfig.url = "github:pjones/kconfig/pjones/force";
    kconfig.flake = false;
  };

  outputs = inputs@{ self, ... }:
    let
      # Systems that can run tests:
      supportedSystems = [
        "aarch64-linux"
        "i686-linux"
        "x86_64-linux"
      ];

      # Function to generate a set based on supported systems:
      forAllSystems = inputs.nixpkgs.lib.genAttrs supportedSystems;

      # Attribute set of nixpkgs for each system:
      nixpkgsFor = forAllSystems (system:
        import inputs.nixpkgs { inherit system; });
    in
    {
      homeManagerModules.plasma-manager = { ... }: {
        imports = [ ./modules ];
      };

      packages = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
          unstable = import inputs.nixpkgs_unstable { inherit system; };
        in
        {
          default = self.packages.${system}.rc2nix;

          demo = (inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              (import test/demo.nix {
                pkgs = nixpkgsFor.x86_64-linux;
                home-manager = inputs.home-manager;
                module = self.homeManagerModules.plasma-manager;
                extraPackages = with self.packages.${system}; [
                  rc2nix
                ];
              })
            ];
          }).config.system.build.vm;

          rc2nix = pkgs.writeShellApplication {
            name = "rc2nix";
            runtimeInputs = with pkgs; [ ruby ];
            text = ''ruby ${script/rc2nix.rb} "$@"'';
          };

          kconfig = unstable.libsForQt5.kdeFrameworks.kconfig.overrideAttrs (_orig: {
            src = inputs.kconfig;
          });

          kconf_update = pkgs.writeShellApplication {
            name = "kconf_update";
            text =
              let kconfig = pkgs.lib.getLib self.packages.${system}.kconfig;
              in ''${kconfig}/libexec/kf5/kconf_update "$@"'';
          };
        });

      apps = forAllSystems (system: {
        default = self.apps.${system}.rc2nix;

        demo = {
          type = "app";
          program = "${self.packages.${system}.demo}/bin/run-plasma-demo-vm";
        };

        rc2nix = {
          type = "app";
          program = "${self.packages.${system}.rc2nix}/bin/rc2nix";
        };
      });

      checks = forAllSystems (system:
        let
          test = path: import path {
            pkgs = nixpkgsFor.${system};
            home-manager = inputs.home-manager;
            module = self.homeManagerModules.plasma-manager;
          };
        in
        {
          default = test ./test/basic.nix;
        });

      devShells = forAllSystems (system: {
        default = nixpkgsFor.${system}.mkShell {
          buildInputs = with nixpkgsFor.${system}; [
            self.packages.${system}.kconf_update
            ruby
            ruby.devdoc
          ];
        };
      });
    };
}
