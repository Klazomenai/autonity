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
        # Default (plain ELF): minimal runtime closure, for deployment via
        # NixOS modules or other environments that set SSL_CERT_FILE /
        # NIX_SSL_CERT_FILE in the service's environment directly. This
        # matches issue #2's "Runtime: ca-certificates only" constraint.
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

          # Match upstream's Linux release build flags (build/ci.go
          # buildFlags): enforce 8MB thread stack. Alpine/musl-based
          # environments default to 128KB which is insufficient for
          # some Autonity code paths.
          ldflags = [
            "-extldflags=-Wl,-z,stack-size=0x800000"
          ];

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
            $out/bin/autonity version | grep -Fxq "Version: ${autonityVersion}"
          '';

          meta = commonMeta;
        };

        # Portable variant: bash wrapper that sets SSL_CERT_FILE and
        # NIX_SSL_CERT_FILE defaults so the binary finds CA trust roots on
        # non-NixOS Linux systems (dev machines, containers, other distros)
        # without requiring the caller to set them. Adds bash + cacert to
        # the runtime closure. NixOS deployments should prefer the default
        # `autonity` package and set cert env vars in the service unit.
        autonity-portable = pkgs.runCommand "autonity-portable-${autonityVersion}"
          {
            nativeBuildInputs = [ pkgs.makeWrapper ];
            inherit (autonity) version;
            pname = "autonity-portable";
            meta = commonMeta // {
              description = "Autonity - Tendermint BFT consensus for EVM (portable: bash wrapper with embedded CA trust roots)";
            };
          }
          ''
            mkdir -p $out/bin
            makeWrapper ${autonity}/bin/autonity $out/bin/autonity \
              --set-default SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
              --set-default NIX_SSL_CERT_FILE ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          '';
      in
      {
        # Default: plain ELF binary, minimal runtime closure (cacert only
        # in the build closure via Go's x/crypto/x509; no bash at runtime).
        # Intended for NixOS module consumption.
        packages.default = autonity;
        packages.autonity = autonity;

        # Portable variant with bash wrapper for non-NixOS systems.
        packages.autonity-portable = autonity-portable;

        # Make `nix flake check` build the default package
        checks.default = autonity;
      }
    );
}
