{ self, lib, ... }: {
  perSystem = { config, self', inputs', pkgs, ... }: {
    devShells = {
      default = pkgs.mkShell {
        inputsFrom = [
            self'.devShells.blog
        ];
      };
    };
  };
}
