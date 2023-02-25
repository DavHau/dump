---
title: "drv-parts"
date: 2023-02-22T18:44:15+07:00
draft: false
---


# [drv-parts](https://github.com/DavHau/drv-parts)

`drv-parts` replaces **`callPackage`**, **`override`**, **`overrideAttrs`**, **`...`** as a mechanism for configuring packages.  
It makes package configuration feel like nixos system configuration.

# Benefits

## No more override functions

Changing options of packages in nixpkgs can require chaining different override functions like this:

```nix
{
  htop-mod = let
    htop-overridden = pkgs.htop.overrideAttrs (old: {
      pname = "htop-mod";
    });
  in
    htop-overridden.override (old: {
      sensorsSupport = false;
    });
}
```

... while doing the same using `drv-parts` looks like this:

```nix
{
  htop-mod = {
    imports = [./htop.nix];
    pname = lib.mkForce "htop-mod";
    sensorsSupport = false;
  };
}
```

See htop module definition [here](/examples/flake-parts/htop/htop.nix).

## Type safety

The following code in nixpkgs mkDerivation mysteriously skips the patches:

```nix
mkDerivation {
  # ...
  dontPatch = "false";
}
```

... while doing the same using `drv-parts` raises an informative type error:

```
A definition for option `[...].dontPatch' is not of type `boolean' [...]
```

## Catch typos

The following code in nixpkgs mkDerivation builds **without** openssl_3.

```nix
mkDerivation {
  # ...
  nativBuildInputs = [openssl_3];
}
```

... while doing the same using `drv-parts` raises an informative error:

```
The option `[...].nativBuildInputs' does not exist
```

## Environment variables clearly defined

`drv-parts` requires a clear distinction between known parameters and user-defined variables.
Defining `SOME_VARIABLE` at the top-level, would raise:

```
The option `[...].SOME_VARIABLE' does not exist
```

Instead it has to be defined under `env.`:

```nix
{
  my-package = {
    # ...
    env.SOME_VARIABLE = "example";
  };
}
```

## Package options documentation

Documentation similar to [search.nixos.org](https://search.nixos.org) can be generated for packages declared via `drv-parts`.

This is not yet implemented.

## Package blueprints

With `drv-parts`, packages don't need to be fully declared. Options can be left without defaults, requiring the consumer to complete the definition.

For example, this can be useful for lang2nix tools, where `src` and `version` are dynamically provided by a lock file parser.

## Freedom of abstraction

The nixos module system gives maintainers more freedom over how packages are split into modules. Separation of concerns can be implemented more easily.
For example, the dependency tree of a package set can be factored out into a separate module, allowing for simpler modification.
