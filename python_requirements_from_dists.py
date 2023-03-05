#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 python3Packages.pkginfo python3Packages.packaging
'''
Given a directory of python source distributions (.tar.gz) and wheels,
return a JSON representation of their dependency tree.

We want to put each python package into a separate derivation,
therefore nix needs to know which of those packages depend on
each other.

We only care about the graph between packages, as we start from
a complete set of python packages in the right version
- resolved & fetched by `pip download`, `mach-nix` or other tools.

That means that version specifiers as in (PEP 440; https://peps.python.org/pep-0508/)
and extras specified in markers (PEP 508; https://peps.python.org/pep-0508/ ) can be
ignored for now.

We rely on `pkginfo` (https://pythonhosted.org/pkginfo/) to read `Requires-Dist`
et al as specified in https://packaging.python.org/en/latest/specifications/core-metadata/#id23
And we use `packaging` (https://packaging.pypa.io/en/stable/index.html) to parse
dependency declarations.

'''

import sys
import tarfile
import json
from pathlib import Path
from collections import OrderedDict

from pkginfo import SDist, Wheel
from packaging.requirements import Requirement
from packaging.utils import parse_sdist_filename


def _is_source_dist(pkg_file):
    return pkg_file.suffixes[-2:] == ['.tar', '.gz']


def get_pkg_info(pkg_file):
    if pkg_file.suffix == '.whl':
        return Wheel(str(pkg_file))
    elif _is_source_dist(pkg_file):
        return SDist(str(pkg_file))


def _is_required_dependency(requirement):
    # We set the extra field to an empty string to effectively ignore all optional
    # dependencies for now.
    return not requirement.marker or requirement.marker.evaluate({'extra': ""})


def get_requirements(pkg_file):
    requirements = [Requirement(req) for req in info.requires_dist]
    # For source distributions which do *not* specify requires_dist,
    # we fallback to parsing requirements.txt
    if not requirements and _is_source_dist(pkg_file):
        if requirements_txt := get_requirements_txt(pkg_file):
            requirements = [
                Requirement(req)
                            for req in requirements_txt.split("\n")
                            if req and not req.startswith("#")]
    requirements = filter(_is_required_dependency, requirements)
    return requirements


def get_requirements_txt(source_dist_file):
    name, version = parse_sdist_filename(source_dist_file.name)
    with tarfile.open(source_dist_file) as tar:
        try:
            with tar.extractfile(f'{name}-{version}/requirements.txt') as f:
                return f.read().decode('utf-8')
        except KeyError as e:
            return


def usage():
    print(f'{sys.argv[0]} <pkgs-directory>')
    sys.exit(1)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        usage()
    pkgs_path = Path(sys.argv[1])
    if not (pkgs_path.exists and pkgs_path.is_dir()):
        usage()

    dependencies = OrderedDict()
    for pkg_file in pkgs_path.iterdir():
        info = get_pkg_info(pkg_file)
        name = info.name.lower()
        dependencies[name] = [req.name.lower() for req in get_requirements(pkg_file)]
    print(json.dumps(dependencies, indent=2))
