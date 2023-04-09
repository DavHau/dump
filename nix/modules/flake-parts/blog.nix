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

    blog = pkgs.runCommandNoCC "blog" {} ''
      mkdir $out
      cd $out
      cp -r ${self + /blog}/* .
      chmod +w -R .

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
        openssh
      ])
      ''
        set -x
        branchOrig=$(git branch --show-current)
        git checkout gh-pages
        rsync -r ${website}/ .
        chmod +w -R .
        git add .
        git commit -m "deploy blog - $(date --rfc-3339=seconds)" || :
        git push
        git checkout "$branchOrig"
      ''
    );

    projectPrefix = "blog_project_";
    fileNames = ["README.md" "Readme.md" "readme.md"];
    getReadmeName = src: l.head (
      l.filter (fn: l.pathExists (src + "/${fn}")) fileNames
    );
    getReadme = src: src + "/${getReadmeName src}";
    projectInputs = l.flip l.filterAttrs inputs (name: _: l.hasPrefix "blog_" name);
    projects = l.flip l.mapAttrs' projectInputs
      (name: src:
        l.nameValuePair (l.removePrefix projectPrefix name) (getReadme src));
    makeHeader = name: ''
      echo "
      ---
      title: "${name}"
      date: $(date --iso-8601)
      draft: false
      ---
      " \
    '';
    copyReadme = name: readme: ''
      set -x
      ${makeHeader name} > $out/${name}.md
      cat ${readme} >> $out/${name}.md
    '';
    allReadmesScript = ''
      mkdir $out
      ${toString (l.mapAttrsToList copyReadme projects)}
    '';
    allReadmes = pkgs.runCommand "all-readmes" {} allReadmesScript;
    update.type = "app";
    update.program = toString (config.writers.writePureShellScript
      (with pkgs; [
        coreutils
      ])
      ''
        set -x
        cp ${allReadmes}/* blog/content/projects/
        chmod +w -R blog/content/projects/
      ''
    );

  in {
    packages.blog = blog;
    devShells.blog = shell;
    apps.blog-deploy = deploy;
    apps.blog-update = update;
  };
}
