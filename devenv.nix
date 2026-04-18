{ pkgs, ... }:

{
  languages.go = {
    enable = true;
    # nixpkgs has no go_1_24 (only 1.23, 1.25, 1.26); using 1.25 — the
    # closest version satisfying go.mod's "go 1.24.0" minimum requirement.
    # Matches the toolchain pinned in flake.nix.
    package = pkgs.go_1_25;
  };

  packages = with pkgs; [
    gcc
    gnumake
    git
  ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    linuxHeaders
  ];

  enterShell = ''
    echo "Autonity development environment"
    echo "Go version: $(go version)"
  '';
}
