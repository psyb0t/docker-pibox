"""pibox — pi-coding-agent adapter for aicodebox."""
from importlib.metadata import PackageNotFoundError, version as _pkg_version

try:
    __version__ = _pkg_version("pibox")
except PackageNotFoundError:
    # Source checkout, package not installed. Don't fall back to a
    # hardcoded number — that's the drift this whole pattern exists to
    # prevent. Use a sentinel so the bug is obvious.
    __version__ = "0.0.0+source"
