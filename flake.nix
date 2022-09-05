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
    many-rs-rev = "79730557ecb0378b8919ea9ccd02f20b41dfe0ce";
    many-framework-rev = "f809ad474858d4e660f9082a9e90a7324f38f8b7";
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
            sha256 = "sha256-2023f77rrlQgqax6UkIIjwHip3XSpSkzWuvmhmWWRM0=";
            date = "2022-08-21";
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
            sha256 = "sha256-ywxVwg9LAuy0t608l2yp30JBoibau3An5eyhQheL+Os=";
          };

          many-framework-src = final.fetchFromGitHub {
            owner = "liftedinit";
            repo = "many-framework";
            rev = many-framework-rev;
            sha256 = "sha256-EBvyKp0L13Wu/Ce+772Pkt3BEd46aSxeHlyjEK3LdGM=";
          };

          many-framework = final.naersk-lib.buildPackage {
            name = "many-framework";
            root = final.many-framework-src;
            buildInputs = [
              final.pkg-config
              final.openssl
              final.llvmPackages.libcxxClang
            ];
            prePatch = ''
              substituteInPlace src/many-ledger/build.rs --replace 'vergen(config).expect("Vergen could not run.")' ""
            '';
            VERGEN_GIT_SHA = many-framework-rev;

            LIBCLANG_PATH = "${final.llvmPackages.libclang.lib}/lib";
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
          export PKCS11_SOFTHSM2_MODULE=${pkgs.softhsm}/lib/softhsm/libsofthsm2.so
        '';
        nativeBuildInputs = [
          pkgs.llvmPackages.libcxxClang
        ];
        buildInputs = [
          pkgs.rust-analyzer
          pkgs.softhsm
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
