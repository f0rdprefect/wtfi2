{
  description = "wtfi2 — What The F*ck Internet: a live, visual network-path diagnostic";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };

      # Read the version from Cargo.toml so the flake can never drift from the crate.
      version = (builtins.fromTOML (builtins.readFile ./Cargo.toml)).package.version;
      description = "Live, visual network-path diagnostic that pinpoints exactly where your connection dies";

      # Linux shells out to these at runtime (ip/iw for link telemetry, ping and
      # traceroute for the probes). None are guaranteed by a stock NixOS install,
      # so the wrapper below puts them on the binary's PATH.
      runtimeTools =
        pkgs: with pkgs; [
          iproute2
          iw
          iputils
          traceroute
        ];

      mkWtfi =
        pkgs:
        pkgs.rustPlatform.buildRustPackage {
          pname = "wtfi2";
          inherit version;
          src = self;

          # Fixed-output pin of the Cargo.lock graph. Regenerate with the fakeHash
          # trick after any dependency change — see "Keeping the flake in sync with
          # Cargo.lock" in README.md.
          cargoHash = "sha256-QURJm65pr3empV8tK5jEBbmp7Uo9XoD89yulflRa8+8=";

          # tests/cli.rs drives the real binary against the live network; the
          # sandbox has none, so the network leg is not meaningful there.
          doCheck = false;

          nativeBuildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.makeWrapper ];

          postInstall = lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
            wrapProgram $out/bin/wtfi \
              --prefix PATH : ${lib.makeBinPath (runtimeTools pkgs)}
          '';

          meta = {
            inherit description;
            homepage = "https://github.com/kanywst/wtfi2";
            license = lib.licenses.mit;
            mainProgram = "wtfi";
            platforms = lib.platforms.linux ++ lib.platforms.darwin;
          };
        };

      app = system: {
        type = "app";
        program = "${self.packages.${system}.wtfi2}/bin/wtfi";
        meta.description = description;
      };
    in
    {
      packages = forAllSystems (system: {
        wtfi2 = mkWtfi (pkgsFor system);
        default = self.packages.${system}.wtfi2;
      });

      overlays.default = final: _prev: {
        wtfi2 = mkWtfi final;
      };

      nixosModules.default = { ... }: {
        nixpkgs.overlays = [ self.overlays.default ];
      };

      apps = forAllSystems (system: {
        default = app system;
        wtfi2 = app system;
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages =
              with pkgs;
              [
                cargo
                rustc
                rustfmt
                clippy
              ]
              ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux (runtimeTools pkgs);
          };
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);
    };
}
