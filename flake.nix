{
  inputs = {
    cargo2nix.url = "github:cargo2nix/cargo2nix/release-0.11.0";
    flake-utils.follows = "cargo2nix/flake-utils";
    nixpkgs.follows = "cargo2nix/nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
    cargo2nix.inputs.rust-overlay.follows = "rust-overlay";
    naersk.url = "github:nix-community/naersk";
    mozillapkgs = {
      url = "github:mozilla/nixpkgs-mozilla";
      flake = false;
    };
  };

  outputs = { cargo2nix, flake-utils, nixpkgs, naersk, mozillapkgs, ... }:
  flake-utils.lib.eachDefaultSystem (system:
  let
    many-rs-rev = "20541988a8722a9bd10e2bcf3cb84dc17e1775e4";
    many-framework-rev = "a8804085bcc28b75ac8333622f217e0da13bc577";
    specification-rev = "6ba25eebec3493340e6537682eb360ba24046042";

    rust-overrides = pkgs: [
      (pkgs.rustBuilder.rustLib.makeOverride {
        name = "cryptoki-sys";
        overrideAttrs = drv: {
          LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
          nativeBuildInputs = [
            pkgs.llvmPackages.libcxxClang
          ];
        };
      })
      (pkgs.rustBuilder.rustLib.makeOverride {
        name = "librocksdb-sys";
        overrideAttrs = drv: {
          LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
          nativeBuildInputs = [
            pkgs.llvmPackages.libcxxClang
          ];
        };
      })
      (pkgs.rustBuilder.rustLib.makeOverride {
        name = "many-ledger";
        overrideAttrs = drv: {
          prePatch = ''
            substituteInPlace build.rs --replace 'vergen(config).expect("Vergen could not run.")' ""
          '';
          VERGEN_GIT_SHA = many-framework-rev;
        };
      })
    ];

    pkgs = import nixpkgs {
      inherit system;
      overlays = [
        cargo2nix.overlays.default

        (final: prev: {
          many-rs-pkgs = let
            rustToolchain = builtins.fromTOML (builtins.readFile "${final.many-rs-src}/rust-toolchain.toml");
          in final.rustBuilder.makePackageSet {
            rustVersion = rustToolchain.toolchain.channel;
            packageFun = import ./many-rs/Cargo.nix;
            workspaceSrc = final.many-rs-src;
            extraRustComponents = rustToolchain.toolchain.components ++ [
              "rust-src"
            ];
            packageOverrides = pkgs: pkgs.rustBuilder.overrides.all ++ (rust-overrides pkgs);
          };

          specification-pkgs = let
            rustToolchain = builtins.fromTOML (builtins.readFile "${final.many-rs-src}/rust-toolchain.toml");
          in final.rustBuilder.makePackageSet {
            rustVersion = rustToolchain.toolchain.channel;
            packageFun = import ./specification/Cargo.nix;
            workspaceSrc = final.specification-src;
            extraRustComponents = rustToolchain.toolchain.components ++ [
              "rust-src"
            ];
          };

          mozilla = final.callPackage ("${mozillapkgs}/package-set.nix") {};

          many-framework-rust = (final.mozilla.rustChannelOf {
            rustToolchain = "${final.many-framework-src}/rust-toolchain.toml";
            sha256 = "sha256-kHjy3d6GgqjU2VZaIWJN+Ih2D5JQJ7b5/3kKU5Rb6H4=";
          }).rust.override {
            extensions = ["rust-src"];
          };

          naersk-lib = naersk.lib."${system}".override {
            cargo = final.many-framework-rust;
            rustc = final.many-framework-rust;
          };

          many-rs-src = final.fetchFromGitHub {
            owner = "liftedinit";
            repo = "many-rs";
            rev = many-rs-rev;
            sha256 = "sha256-f6ULbOt3mb5IBeaXWDqttPWBWH1/0r3URFJ+HQVtcNs=";
          };

          many-framework-src = final.fetchFromGitHub {
            owner = "liftedinit";
            repo = "many-framework";
            rev = many-framework-rev;
            sha256 = "sha256-RY5cqa35J+Cmps8LG4Evvq6cH0oJkrOLhoWwdMJymMk=";
          };

          many-framework = final.naersk-lib.buildPackage {
            pname = "many-framework";
            root = final.many-framework-src;
          };

          specification-src = final.fetchFromGitHub {
            owner = "many-protocol";
            repo = "specification";
            rev = specification-rev;
            sha256 = "sha256-ngoN2iSg9hldblqaoJA3n3TC4ATTzHPfvNW9jgbytt0=";
          };
        })
      ];
    };
  in {
    packages = {
      many-rs = (pkgs.many-rs-pkgs.workspace.many {}).bin;
      many-framework = pkgs.many-framework;
      specification = (pkgs.specification-pkgs.workspace.spectests {}).bin;
    };
    devShells = {
      many-rs = pkgs.many-rs-pkgs.workspaceShell {
        shellHook = ''
          export LIBCLANG_PATH=${pkgs.llvmPackages.libclang.lib}/lib
        '';
        nativeBuildInputs = [
          pkgs.llvmPackages.libcxxClang
        ];
        buildInputs = [
          pkgs.rust-analyzer
        ];
      };
      specification = pkgs.specification-pkgs.workspaceShell {
        shellHook = ''
          export LIBCLANG_PATH=${pkgs.llvmPackages.libclang.lib}/lib
        '';
        nativeBuildInputs = [
          pkgs.llvmPackages.libcxxClang
        ];
        buildInputs = [
          pkgs.rust-analyzer
        ];
      };
      many-framework = pkgs.mkShell {
        inputsFrom = [ pkgs.many-framework ];
        shellHook = ''
          export LIBCLANG_PATH=${pkgs.llvmPackages.libclang.lib}/lib
        '';
        nativeBuildInputs = [
          pkgs.llvmPackages.libcxxClang
          pkgs.pkg-config
        ];
        buildInputs = [
          pkgs.rust-analyzer
          pkgs.openssl
        ];
      };
    };

    # Debugging
    inherit pkgs;
  });
}
