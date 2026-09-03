# SPDX-License-Identifier: Apache-2.0
"""Build the UniDAV Cython extension over the stable C ABI."""
import os
import shutil
import subprocess
import sys

from Cython.Build import cythonize
from setuptools import Extension, setup

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PACKAGE = os.path.join(HERE, "unidav")
VENDOR_DIR = os.path.join(HERE, "_nimsrc")
NIMBLE_FILE = "UniDAV.nimble"
VENDOR_FILES = [NIMBLE_FILE, "config.nims"]
VENDOR_DIRS = ["src", "include", "csrc"]

if sys.platform == "win32":
    LIBRARY, BUNDLED, LINK_ARGS, NIMBLE_TASK = "UniDAV.lib", False, [], "clibMsvc"
elif sys.platform == "darwin":
    LIBRARY, BUNDLED, LINK_ARGS, NIMBLE_TASK = "libUniDAV.dylib", True, ["-Wl,-rpath,@loader_path"], "clib"
else:
    LIBRARY, BUNDLED, LINK_ARGS, NIMBLE_TASK = "libUniDAV.so", True, ["-Wl,-rpath,$ORIGIN"], "clib"


def vendor_nim_source():
    if os.path.exists(VENDOR_DIR):
        shutil.rmtree(VENDOR_DIR)
    os.makedirs(VENDOR_DIR)
    for filename in VENDOR_FILES:
        shutil.copy2(os.path.join(ROOT, filename), os.path.join(VENDOR_DIR, filename))
    for dirname in VENDOR_DIRS:
        shutil.copytree(os.path.join(ROOT, dirname), os.path.join(VENDOR_DIR, dirname))


def nim_project_dir():
    if os.path.exists(os.path.join(ROOT, NIMBLE_FILE)):
        return ROOT
    if os.path.exists(os.path.join(VENDOR_DIR, NIMBLE_FILE)):
        return VENDOR_DIR
    return None


def ensure_lib_built():
    prebuilt = os.path.join(ROOT, LIBRARY)
    if os.path.exists(prebuilt):
        return prebuilt
    project = nim_project_dir()
    if project is None:
        raise SystemExit(f"setup.py: {prebuilt} not found; run `nimble {NIMBLE_TASK}` first.")
    built = os.path.join(project, LIBRARY)
    if not os.path.exists(built):
        try:
            subprocess.check_call(["nimble", "install", "-y"], cwd=project)
            subprocess.check_call(["nimble", NIMBLE_TASK], cwd=project)
        except FileNotFoundError as error:
            raise SystemExit("setup.py: Nim/nimble is required to build UniDAV from source.") from error
        except subprocess.CalledProcessError as error:
            raise SystemExit(f"setup.py: `nimble {NIMBLE_TASK}` failed: {error}") from error
    if not os.path.exists(built):
        raise SystemExit(f"setup.py: `nimble {NIMBLE_TASK}` did not produce {built}")
    return built


if "sdist" in sys.argv:
    vendor_nim_source()
    library_dir = ROOT
else:
    library_path = ensure_lib_built()
    library_dir = os.path.dirname(library_path)
    if BUNDLED:
        os.makedirs(PACKAGE, exist_ok=True)
        shutil.copy2(library_path, os.path.join(PACKAGE, LIBRARY))

source_pyx = os.path.join("unidav", "_core.pyx")
source_c = os.path.join("unidav", "_core.c")
source = source_pyx if os.path.exists(os.path.join(HERE, source_pyx)) else source_c
include_dir = os.path.join(ROOT, "include")
if not os.path.isdir(include_dir):
    include_dir = os.path.join(VENDOR_DIR, "include")
extension = Extension("unidav._core", [source], include_dirs=[include_dir],
                      library_dirs=[library_dir], libraries=["UniDAV"],
                      extra_link_args=LINK_ARGS)
extensions = cythonize([extension], language_level=3) if source.endswith(".pyx") else [extension]
setup(ext_modules=extensions, include_package_data=True,
      package_data={"unidav": [LIBRARY] if BUNDLED else []},
      exclude_package_data={"unidav": ["_core.c"]}, zip_safe=False)
