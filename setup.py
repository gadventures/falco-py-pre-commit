from __future__ import annotations

import platform
import sys

from setuptools import setup

machine = platform.machine().lower()
machine = {"amd64": "x86_64", "arm64": "arm64"}.get(machine, machine)
current_platform = (sys.platform, machine)
supported_platforms = {
    ("darwin", "arm64"),
    ("darwin", "x86_64"),
    ("linux", "aarch64"),
    ("linux", "x86_64"),
}
if current_platform not in supported_platforms:
    raise RuntimeError(
        "falco-py-pre-commit supports only macOS or Linux on x86_64 or arm64; "
        f"got {current_platform[0]}/{current_platform[1]}",
    )

try:
    from setuptools.command.bdist_wheel import bdist_wheel as orig_bdist_wheel
except ImportError:
    cmdclass = {}
else:

    class bdist_wheel(orig_bdist_wheel):
        def finalize_options(self):
            orig_bdist_wheel.finalize_options(self)
            # Mark us as not a pure python package: we ship a downloaded,
            # platform-specific `falco` binary.
            self.root_is_pure = False

        def get_tag(self):
            _, _, plat = orig_bdist_wheel.get_tag(self)
            # The only python here is the tiny wrapper; the wheel is
            # platform-specific because of the bundled binary.
            return "py3", "none", plat

    cmdclass = {"bdist_wheel": bdist_wheel}

setup(cmdclass=cmdclass)
