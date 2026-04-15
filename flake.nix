{
  description = "Autonity - Tendermint BFT consensus for EVM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    # Restricted to Linux: meta.platforms = platforms.linux below means
    # builds on Darwin would fail with "unsupported platform". Both x86_64
    # and aarch64 Linux are supported by Go's CGO toolchain.
    flake-utils.lib.eachSystem [
      "x86_64-linux"
      "aarch64-linux"
    ] (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        autonityVersion = "1.1.2";

        # Pin Go toolchain. go.mod requires Go 1.24.0 minimum. nixpkgs
        # currently exposes buildGo123Module, buildGo125Module, and
        # buildGo126Module — there is no buildGo124Module — so we pin to
        # buildGo125Module as the closest available version that satisfies
        # the go.mod minimum. Note: passing `go = pkgs.go_1_25` to
        # pkgs.buildGoModule is ineffective because pkgs.buildGoModule is
        # aliased to buildGo126Module in nixpkgs and the parameter doesn't
        # override the underlying alias.
        autonity = pkgs.buildGo125Module {
          pname = "autonity";
          version = autonityVersion;
          src = ./.;

          # Hash of the Go module proxy-vendored dependencies.
          # To recompute: set vendorHash = pkgs.lib.fakeHash, run nix build,
          # copy the correct hash from the error.
          vendorHash = "sha256-WLqqnqxWkUZjIi8MzHWqCv0omlJZKowCIo1eBr/1w0I=";
          proxyVendor = true;

          subPackages = [ "cmd/autonity" ];

          env = {
            # CGO required for embedded libsecp256k1 (crypto/secp256k1)
            CGO_ENABLED = "1";
            # Force the pinned Go version above; without this, Go's auto
            # toolchain selection can pick a different version present in
            # the build closure, defeating the point of pinning.
            GOTOOLCHAIN = "local";
          };

          nativeBuildInputs = with pkgs; [
            gcc
            makeWrapper
          ];

          # Wrap the binary so it finds CA trust roots on non-NixOS systems.
          # Autonity makes outbound HTTPS connections (bootnodes, RPC clients,
          # cloud SDKs). Without this, the binary works on NixOS (which exposes
          # certs at /etc/ssl/certs) but fails on plain Linux distributions.
          postFixup = ''
            wrapProgram $out/bin/autonity \
              --set-default SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
              --set-default NIX_SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          '';

          # Skip upstream Go tests during Nix build; CI handles them
          doCheck = false;

          doInstallCheck = true;
          installCheckPhase = ''
            $out/bin/autonity version | grep -q "Version: ${autonityVersion}"
          '';

          meta = with pkgs.lib; {
            description = "Autonity - Tendermint BFT consensus for EVM";
            homepage = "https://github.com/autonity/autonity";
            license = with licenses; [
              lgpl3Plus
              gpl3Plus
            ];
            mainProgram = "autonity";
            platforms = platforms.linux;
          };
        };
      in
      {
        packages.default = autonity;
        packages.autonity = autonity;

        # Make `nix flake check` build the package and run installCheckPhase
        checks.default = autonity;
      }
    );
}
