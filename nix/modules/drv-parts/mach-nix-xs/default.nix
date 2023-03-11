{config, lib, drv-parts, ...}: let

  l = lib // builtins;
  python = config.deps.python;
  cfg = config.mach-nix;
  packageName = config.public.name;

  # For a given name, return the path containing the downloaded file
  getDistDir = name: "${cfg.pythonSources.names}/${name}";

  # (IFD) Get the dist file for a given name by looking inside (pythonSources)
  getDistFile = name: let
    distDir = getDistDir name;
    distFile = l.head (l.attrNames (builtins.readDir distDir));
  in
    "${distDir}/${distFile}";

  # Extract the version from a dist's file name
  getVersion = file: let
    base = l.pipe file [
      (l.removeSuffix ".tgx")
      (l.removeSuffix ".tar.gz")
      (l.removeSuffix ".zip")
      (l.removeSuffix ".whl")
    ];
    version = l.last (l.splitString "-" base);
  in
    version;

  # (IFD) For each dist we need to recall:
  #   - the type (wheel or sdist)
  #   - the version (only needed for sdist, so we can build a wheel)
  getDistInfo = name: let
    file = getDistFile name;
  in
    if l.hasSuffix ".whl" file
    then "wheel"
    else getVersion file;

  preparedWheels =
    let
      filterAttrs = l.flip l.filterAttrs;
      mapAttrs = l.flip l.mapAttrs;
      distInfos = config.eval-cache.content.mach-nix.dists;

      # Validate Substitutions. Allow only names that we actually depend on.
      unknownSubstitutions = l.attrNames (l.removeAttrs cfg.substitutions (l.attrNames distInfos));
      substitutions =
        if unknownSubstitutions == []
        then cfg.substitutions
        else throw ''
              ${"\n"}The following substitutions for python derivation '${packageName}' will not have any effect. There are no dependencies with such names:
              - ${lib.concatStringsSep "\n  - " unknownSubstitutions}
        '';

      # separate 2 types of downloaded files: sdist, wheel
      # key: name; val: {version or "wheel"}
      wheelInfos = filterAttrs distInfos (name: ver: ver == "wheel");
      sdistInfos = filterAttrs distInfos (name: ver: ! wheelInfos ? ${name});

      # get the paths of all downloaded wheels
      downloadedWheels = mapAttrs wheelInfos (name: ver: getDistDir name);
      # Only build sdists which are not substituted via config.substitutions and which aren't the toplevel
      # package.
      sdistsToBuild = filterAttrs sdistInfos (name: ver: (! substitutions ? ${name}) && name != packageName);
      builtWheels = mapAttrs sdistsToBuild (name: ver: mkWheelDist name ver (getDistDir name));

      # Usually references to buildInputs would get lost in the dist output.
      # Patch wheels to ensure build inputs remain dependencies of the `dist` output
      # Those references are needed for the final autoPatchelfHook to find the required deps.
      patchedWheels = mapAttrs substitutions (name: dist: dist.overridePythonAttrs (old: {postFixup = "ln -s $out $dist/out";}));
    in
      { inherit patchedWheels downloadedWheels builtWheels; };

  # The final dists we want to install.
  # A mix of:
  #   - downloaded wheels
  #   - downloaded sdists built into wheels (see above)
  #   - substitutions from nixpkgs patched for compat with autoPatchelfHook
  finalDistsPaths =
    preparedWheels.downloadedWheels // (l.mapAttrs (_: drv: drv.public.out.dist) config.mach-nix.drvs);


  # build a wheel for a given sdist
  mkWheelDist = name: version: distDir: let
    manualSetupDeps =
      lib.mapAttrs
        (name: deps: map (dep: finalDistsPaths.${dep}) deps)
        cfg.manualSetupDeps;
  in {config, ...}: {
    imports = [
      drv-parts.modules.drv-parts.mkDerivation
      ../buildPythonPackage
      ./interface.nix
      ../eval-cache
      ../nixpkgs-overrides
    ];
    config = {
      nixpkgs-overrides.enable = true;
      deps = {nixpkgs, ...}: l.mapAttrs (_: l.mkDefault) ({
        inherit python;
        inherit (nixpkgs)
          autoPatchelfHook
          stdenv
        ;
      });

      public = {
        inherit name version;
      };
      buildPythonPackage = {
        format = "setuptools";
        pipInstallFlags =
          (map (distDir: "--find-links ${distDir}") manualSetupDeps.${name} or [])
          ++ (map (dep: "--find-links ${finalDistsPaths.${dep}}") dependencyTree.${name} or []);
      };
      mkDerivation = {
        # distDir will contain a single file which is the src
        preUnpack = ''export src="${distDir}"/*'';
        nativeBuildInputs = [config.deps.autoPatchelfHook];
        # ensure build inputs are propagated for autopPatchelfHook
        postFixup = "ln -s $out $dist/out";
      };
      # TODO If setup deps have been specified manually, we need to remove the
      #   propagatedBuildInputs from nixpkgs to prevent collisions.
      #// lib.optionalAttrs (manualSetupDeps ? ${name}) {
      #  propagatedBuildInputs = [];
      #};
    };
  };

  dependenciesFile = "${cfg.pythonSources}/dependencies.json";
  dependencies = l.filter (d: d.name != packageName) (l.fromJSON (l.readFile dependenciesFile));
  dependencyTree = l.listToAttrs (
    (l.flip map) dependencies
      (dep: l.nameValuePair dep.name dep.dependencies));


makeModuleFromDerivation = _name: drv:
  drv-parts.lib.makeModule {
    packageFunc = drv;
    # TODO: if `overridePythonAttrs` is used here, the .dist output is missing
    #   Maybe a bug in drv-parts?
    overrideFuncName = "overrideAttrs";
    modules = [
      {deps = {inherit (config.deps) stdenv;};}
    ];
  };

in {

  imports = [
    drv-parts.modules.drv-parts.mkDerivation
    ../buildPythonPackage
    ./interface.nix
    ../eval-cache
  ];

  config = {

    mach-nix.drvs = (l.mapAttrs makeModuleFromDerivation preparedWheels.patchedWheels) // preparedWheels.builtWheels;
    mach-nix.dists =
      l.mapAttrs
      (name: _: getDistInfo name)
      (l.readDir cfg.pythonSources.names);

    mach-nix.dependencyTree = dependencyTree;

    deps = {nixpkgs, ...}: l.mapAttrs (_: l.mkDefault) (
      {
        inherit (nixpkgs)
          autoPatchelfHook
          stdenv
          ;
        manylinuxPackages = nixpkgs.pythonManylinuxPackages.manylinux1;
        fetchPythonRequirements = nixpkgs.callPackage ../../../pkgs/fetchPythonRequirements {};

        runCommand = nixpkgs.runCommand;
        pip = nixpkgs.python3Packages.pip;
      }
    );

    eval-cache.fields = {
      mach-nix.dists = true;
      mach-nix.dependencyTree = true;
    };

    eval-cache.invalidationFields = {
      mach-nix.pythonSources = true;
    };

    buildPythonPackage = {
      pipInstallFlags =
        ["--ignore-installed"]
        ++ (
          map (distDir: "--find-links ${distDir}")
          (l.attrValues finalDistsPaths)
        );
    };

    mkDerivation = {
      doCheck = false;
      dontPatchELF = l.mkDefault true;
      dontStrip = l.mkDefault true;


      nativeBuildInputs = [
        config.deps.autoPatchelfHook
      ];

      buildInputs =
        (with config.deps; [
          manylinuxPackages
        ]);

      passthru = {
        inherit (config.mach-nix) pythonSources;
        dists = finalDistsPaths;
      };
    };
  };
}
