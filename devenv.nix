{ pkgs, ... }:

{
  languages.go = {
    enable = true;
    package = pkgs.go_1_24;
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
