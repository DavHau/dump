{ self, lib, inputs, ... }: {
  perSystem = { config, self', inputs', pkgs, ... }: let
    l = lib // builtins;

    themesDir = pkgs.runCommand "themes" {} ''
      mkdir $out
      ln -s ${inputs.hugo-theme} $out/theme
    '';

    # Wrap hugo to include the theme from the flake input (no submodules, yey)
    hugoPkg = pkgs.writeScriptBin "hugo"
      ''
        ${pkgs.hugo}/bin/hugo --themesDir ${themesDir} "$@"
      '';

    hugo = "${hugoPkg}/bin/hugo";
    theme = inputs.hugo-theme;

    blog = pkgs.runCommandNoCC "blog" {} ''
      mkdir $out
      cd $out
      cp -r ${self + /blog}/* .
      chmod +w -R .
      mkdir ./themes
      cp -r ${theme} ./themes/theme

      ${hugo}
    '';

    shell = pkgs.mkShell {
      packages = [
        hugoPkg
      ];
    };

    website = pkgs.runCommand "website" {} ''
      cp -r ${self}/blog/* .
      chmod -R +w .
      ${hugoPkg}/bin/hugo
      mv public $out
    '';

    deploy.type = "app";
    deploy.program = toString (config.writers.writePureShellScript
      (with pkgs; [
        coreutils
        gitMinimal
        rsync
      ])
      ''
        set -x
        git checkout gh-pages
        rsync -r ${website}/ .
        chmod +w -R .
        git add .
        git commit -m "deploy blog - $(date --rfc-3339=seconds)"
        git push
      ''
    );

  in {
    packages.blog = blog;
    devShells.blog = shell;
    apps.deploy-blog = deploy;
  };
}
