{
  description = "Object-oriented programming, implemented from scratch in x86-64 assembly";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # The exercises are x86-64 System V ELF. Dev shells are offered more
      # widely so the docs/tooling remain usable elsewhere.
      devSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      buildSystems = [ "x86_64-linux" ];

      forSystems = systems: f:
        nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forSystems devSystems (system: pkgs: {
        default = pkgs.mkShell {
          name = "oo-asm";

          packages = with pkgs; [
            nasm
            gnumake
            binutils
            gdb
            file
          ] ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
            valgrind
            strace
          ];

          shellHook = ''
            echo "oo-asm dev shell"
            echo "  make          # assemble + link every exercise"
            echo "  make test     # run every exercise, diff against expected.txt"
            echo "  make list     # show the exercise ladder"
            ${pkgs.lib.optionalString (!pkgs.stdenv.hostPlatform.isx86_64 || !pkgs.stdenv.hostPlatform.isLinux) ''
              echo
              echo "WARNING: exercises target x86_64-linux; this host is ${system}."
            ''}
          '';
        };
      });

      packages = forSystems buildSystems (system: pkgs: rec {
        default = exercises;

        exercises = pkgs.stdenv.mkDerivation {
          pname = "oo-asm-exercises";
          version = "0.1.0";
          src = self;

          nativeBuildInputs = [ pkgs.nasm ];

          buildPhase = ''
            runHook preBuild
            make all
            runHook postBuild
          '';

          doCheck = true;
          checkPhase = ''
            runHook preCheck
            make test
            runHook postCheck
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            for bin in exercises/*/build/*; do
              [ -x "$bin" ] && [ -f "$bin" ] && install -Dm755 "$bin" "$out/bin/$(basename "$bin")"
            done
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Progressive exercises implementing an object system in x86-64 assembly";
            platforms = [ "x86_64-linux" ];
            license = licenses.mit;
          };
        };
      });

      checks = forSystems buildSystems (system: pkgs: {
        exercises = self.packages.${system}.exercises;
      });

      formatter = forSystems devSystems (system: pkgs: pkgs.nixpkgs-fmt);
    };
}
