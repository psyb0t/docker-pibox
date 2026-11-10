# Python style

Applies to `pibox/pibox/` and `pibox/tests/`.

- Target Python 3.12 or newer (`requires-python` in `pibox/pyproject.toml`); the base image runs 3.14. `adapter.py` and the tests start with `from __future__ import annotations`; keep that and type every function signature.
- `make lint-python` runs `ruff check` and `pyright` inside `psyb0t/aicodebox:v0.18.4` with the versions pinned in the Makefile's `PY_DEV_TOOLS`. Keep those pins equal to the `dev` dependency group in `pyproject.toml`. Both checks must pass with zero findings.
- The adapter package has no runtime dependencies (`dependencies = []`). Import only the standard library and `aicodebox`, which the base image provides. Adding a dependency means installing it in both Dockerfiles, because they install the package with `--no-deps`.
- Module-level constants for limits, paths and patterns (`MAX_MODEL_ID_LENGTH`, `CUSTOM_PROVIDER_STATE_PATH`, `CUSTOM_PROVIDER_NAME_RE`).
- Log with `logging.getLogger(__name__)` and `%s` arguments, never f-strings in log calls. Pass user-controlled values through `_truncate` so prompts, schemas and provider errors cannot flood the log or land in it whole.
- Raise `ValueError` with the offending value and the allowed set for invalid requests. The base calls `validate` before every run, and API mode turns the error into HTTP 422.
- `__version__` comes from package metadata. Never hardcode a version in Python.
