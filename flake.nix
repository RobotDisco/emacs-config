{
  description = "Gaelan's emacs packages and config";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-21.11";

    emacs-overlay.url = "github:nix-community/emacs-overlay";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, emacs-overlay, home-manager, ... }:
    let
      inherit (nixpkgs) lib;

      # These are the platforms I develop for
      systems = ["x86_64-linux" "x86_64-darwin"];

      # Given a function f, iterate over our list of supported systems to
      # generate a function that, given a _individual_ system name, generates
      # a flake-compliant map. This likely collects the outputs for each system
      # in a flake-compliant way.
      forEachSystem = f: lib.genAttrs systems (system: f system);

      # Generate nixpkgs for each platform that this flake might be run on
      nixpkgsForEachSystem = forEachSystem (system: import nixpkgs {
        inherit system;
        # See below for what we are overriding
        overlays = [ self.overlay ];
      });
    in
      {
        # These are the packages we are going to offer
        overlay = final: prev:
          (emacs-overlay.overlay final prev) // rec {
            # Generate custom emacs packages from our .emacs.d
            emacsEnv = final.emacsWithPackagesFromUsePackage {
              package = final.emacsNativeComp;

              config = ./init.org;
              alwaysEnsure = false;
            };

            emacsConfig = (prev.emacsPackagesFor emacsEnv.emacs) .callPackage ./emacs-config.nix ({
              packageRequires = emacsEnv.explicitRequires;
            } // lib.optionalAttrs (self ? lastModifiedDate) {
              version = lib.substring 0 8 self.lastModifiedDate;
            });
          };

        # These are the packages this flake offers
        packages = forEachSystem (system: { inherit (nixpkgsForEachSystem.${system}) emacsConfig emacsEnv; });
        defaultPackage = forEachSystem (system: self.packages.${system}.emacsConfig);

        # We use home-manager to place our config in the user's home directory
        homeManagerModules = { emacsConfig = import ./home-manager.nix; };
        homeConfigurations = forEachSystem (system: home-manager.lib.homeManagerConfiguration {
          # This is a test configuration I guess?
          inherit system;
          pkgs = nixpkgsForEachSystem.${system};
          username = "test";
          homeDirectory = "/home/test";
          extraModules = [ self.homeManagerModules.emacsConfig ];
          configuration = {
            gaelan.emacs.config = {
              enable = true;
            };
          };
        });

        # Make sure home-manager component of this flake works?
        checks = forEachSystem(system: {
          build-home-configuration =
            self.homeConfigurations.${system}.activationPackage;
        });

        # Generate a development environment for developing emacs scripts
        devShell = forEachSystem
          (system:
            let
              pkgs = nixpkgsForEachSystem.${system};

              # Handy dandy shell script
              testEmacsConfig = pkgs.writeShellScriptBin "test-emacs-config" ''
                set -euo pipefail
                export XDG_CONFIG_HOME=$(mktemp -td xdg-config.XXXXXXXXXX)
                mkdir -p $XDG_CONFIG_HOME/emacs
                ${pkgs.xorg.lndir}/bin/lndir -silent ${pkgs.emacsConfig} $XDG_CONFIG_HOME/emacs
                ln -s $HOME/.config/fontconfig $XDG_CONFIG_HOME/.
                ${pkgs.emacsEnv}/bin/emacs "$@"
              '';

              # It's more convenient to pull pre-built packages from cachix than regenerate it ourselves.
              # We should update it every so often.
              updateCaches = pkgs.writeShellScriptBin "update-caches" ''
                ${pkgs.cachix}/bin/cachix use -O . nix-community
              '';
            in pkgs.mkShell {
              nativeBuildInputs = with pkgs; [
                git
                nixpkgs-fmt

                testEmacsConfig
                updateCaches
              ];
            });
      };
}
