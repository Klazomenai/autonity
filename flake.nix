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

        commonMeta = with pkgs.lib; {
          description = "Autonity - Tendermint BFT consensus for EVM";
          homepage = "https://github.com/autonity/autonity";
          # The cmd/autonity binary is GPLv3-or-later (per source headers:
          # "version 3 of the License, or (at your option) any later version").
          # The library code under non-cmd/ paths is LGPLv3, but is not
          # separately built here.
          license = licenses.gpl3Plus;
          mainProgram = "autonity";
          platforms = platforms.linux;
        };

        # Pin Go toolchain. go.mod requires Go 1.24.0 minimum. nixpkgs
        # currently exposes buildGo123Module, buildGo125Module, and
        # buildGo126Module — there is no buildGo124Module — so we pin to
        # buildGo125Module as the closest available version that satisfies
        # the go.mod minimum. Note: passing `go = pkgs.go_1_25` to
        # pkgs.buildGoModule is ineffective because pkgs.buildGoModule is
        # aliased to buildGo126Module in nixpkgs and the parameter doesn't
        # override the underlying alias.
        #
        # Unwrapped variant: a plain ELF binary, suitable for tooling that
        # doesn't tolerate the bash-script wrapper (debuggers, container
        # base images, symbol checkers).
        autonityUnwrapped = pkgs.buildGo125Module {
          pname = "autonity-unwrapped";
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

          nativeBuildInputs = [ pkgs.gcc ];

          # Skip upstream Go tests during Nix build; CI handles them
          doCheck = false;

          doInstallCheck = true;
          installCheckPhase = ''
            $out/bin/autonity version | grep -q "Version: ${autonityVersion}"
          '';

          meta = commonMeta // {
            description = "Autonity - Tendermint BFT consensus for EVM (unwrapped, no cacert)";
          };
        };

        # Default wrapped variant: bash wrapper that sets SSL_CERT_FILE and
        # NIX_SSL_CERT_FILE defaults so the binary finds CA trust roots on
        # non-NixOS systems. Autonity makes outbound HTTPS connections
        # (bootnodes, RPC clients, cloud SDKs).
        autonity = pkgs.runCommand "autonity-${autonityVersion}"
          {
            nativeBuildInputs = [ pkgs.makeWrapper ];
            inherit (autonityUnwrapped) version;
            pname = "autonity";
            meta = commonMeta;
            passthru.unwrapped = autonityUnwrapped;
          }
          ''
            mkdir -p $out/bin
            makeWrapper ${autonityUnwrapped}/bin/autonity $out/bin/autonity \
              --set-default SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
              --set-default NIX_SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          '';
      in
      {
        packages.default = autonity;
        packages.autonity = autonity;
        # Plain ELF binary without bash wrapper — for tooling that needs it.
        packages.autonity-unwrapped = autonityUnwrapped;

        # Make `nix flake check` build the wrapped package
        checks.default = autonity;
      }
    );
}
