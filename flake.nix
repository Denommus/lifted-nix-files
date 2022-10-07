{
  inputs = {
    cargo2nix.url = "github:cargo2nix/cargo2nix/unstable";
    flake-utils.follows = "cargo2nix/flake-utils";
    nixpkgs.follows = "cargo2nix/nixpkgs";
  };

  outputs = { cargo2nix, flake-utils, nixpkgs, ... }:
  flake-utils.lib.eachDefaultSystem (system:
  let
    many-rs-rev = "4a4de79e2e90a55b128584bc1d6e43b3415f8f14";
    many-rs-sha256 = "sha256-pHjHmWUmFLk46jDrCSztFmbxJzggJkYqn2yknmJ6CV4=";
    many-framework-rev = "957c6c77018381cc5706b27a010c85c57c12acce";
    many-framework-sha256 = "sha256-LjutJecDensP6GavPoPztvLKIAJ2lqut+sEf/F3n8Gk=";
    specification-rev = "6ba25eebec3493340e6537682eb360ba24046042";
    specification-sha256 = "sha256-ngoN2iSg9hldblqaoJA3n3TC4ATTzHPfvNW9jgbytt0=";
    many-fuzzy-rev = "9137cda28387c834e0ba897d54697ac51f41e6d0";
    many-fuzzy-sha256 = "sha256-z0PL1AjolPf+qOtbrpUf7uOeNb7lrsCzBUWXDYTBV7U=";

    pkgs = import nixpkgs {
      inherit system;
      overlays = [ cargo2nix.overlays.default ];
    };

    many-rs-src = pkgs.fetchFromGitHub {
      owner = "liftedinit";
      repo = "many-rs";
      rev = many-rs-rev;
      sha256 = many-rs-sha256;
    };

    many-framework-src = pkgs.fetchFromGitHub {
      owner = "liftedinit";
      repo = "many-framework";
      rev = many-framework-rev;
      sha256 = many-framework-sha256;
    };

    many-fuzzy-src = pkgs.fetchFromGitHub {
      owner = "liftedinit";
      repo = "many-fuzzy";
      rev = many-fuzzy-rev;
      sha256 = many-fuzzy-sha256;
    };

    specification-src = pkgs.fetchFromGitHub {
      owner = "many-protocol";
      repo = "specification";
      rev = specification-rev;
      sha256 = specification-sha256;
    };

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

    many-rs-pkgs = let
      rustToolchain = builtins.fromTOML (builtins.readFile "${many-rs-src}/rust-toolchain.toml");
    in pkgs.rustBuilder.makePackageSet {
      rustVersion = rustToolchain.toolchain.channel;
      packageFun = import ./many-rs/Cargo.nix;
      workspaceSrc = many-rs-src;
      extraRustComponents = rustToolchain.toolchain.components ++ [
        "rust-src"
      ];
      packageOverrides = pkgs: pkgs.rustBuilder.overrides.all ++ (rust-overrides pkgs);
    };

    many-framework-pkgs = let
      rustToolchain = builtins.fromTOML (builtins.readFile "${many-framework-src}/rust-toolchain.toml");
    in pkgs.rustBuilder.makePackageSet {
      rustChannel = rustToolchain.toolchain.channel;
      packageFun = import ./many-framework/Cargo.nix;
      workspaceSrc = many-framework-src;
      extraRustComponents = rustToolchain.toolchain.components ++ [
        "rust-src"
      ];
      packageOverrides = pkgs: pkgs.rustBuilder.overrides.all ++ (rust-overrides pkgs);
    };

    many-fuzzy-pkgs = let
      rustToolchain = builtins.fromTOML (builtins.readFile "${many-rs-src}/rust-toolchain.toml");
    in pkgs.rustBuilder.makePackageSet {
      rustChannel = rustToolchain.toolchain.channel;
      packageFun = import ./many-fuzzy/Cargo.nix;
      workspaceSrc = many-fuzzy-src;
      packageOverrides = pkgs: pkgs.rustBuilder.overrides.all ++ (rust-overrides pkgs);
      ignoreLockHash = true;
      extraRustComponents = [
        "rustfmt"
        "rustc"
        "clippy"
        "llvm-tools-preview"
        "rust-src"
      ];
    };

    specification-pkgs = let
      rustToolchain = builtins.fromTOML (builtins.readFile "${many-rs-src}/rust-toolchain.toml");
    in pkgs.rustBuilder.makePackageSet {
      rustVersion = rustToolchain.toolchain.channel;
      packageFun = import ./specification/Cargo.nix;
      workspaceSrc = pkgs.specification-src;
      extraRustComponents = rustToolchain.toolchain.components ++ [
        "rust-src"
      ];
    };
  in {
    packages = {
      many-rs = (many-rs-pkgs.workspace.many {}).bin;
      many-framework = pkgs.buildEnv {
        name = "many-framework";
        paths = [
          (many-framework-pkgs.workspace.ledger {}).bin
          (many-framework-pkgs.workspace.many-ledger {}).bin
          (many-framework-pkgs.workspace.many-abci {}).bin
          (many-framework-pkgs.workspace.many-kvstore {}).bin
        ];
      };
      many-fuzzy = (many-fuzzy-pkgs.workspace.many-fuzzy {}).bin;
      specification = (pkgs.specification-pkgs.workspace.spectests {}).bin;
    };
    devShells = {
      many-rs = many-rs-pkgs.workspaceShell {
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
      many-fuzzy = many-fuzzy-pkgs.workspaceShell {
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
      many-framework = many-framework-pkgs.workspaceShell {
        shellHook = ''
          export LIBCLANG_PATH=${pkgs.llvmPackages.libclang.lib}/lib
        '';
        nativeBuildInputs = [
          pkgs.llvmPackages.libcxxClang
        ];
        buildInputs = [
          pkgs.rust-analyzer
          pkgs.bats
          pkgs.tendermint
          pkgs.tmux
          ((many-rs-pkgs.workspace.many {}).bin)
          ((many-fuzzy-pkgs.workspace.many-fuzzy {}).bin)
        ];
      };
    };

    # Debugging
    inherit pkgs;
  });
}
