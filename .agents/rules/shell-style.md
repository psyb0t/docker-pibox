# Shell style

Applies to `wrapper.sh`, `install.sh`, `pibox-entrypoint.sh`, `pibox/scripts/*.sh`, `pibox/init.d/*.sh`, `scripts/github-action.sh`, `test.sh` and `tests/*.sh`.

- The e2e suite (`test.sh`, `tests/common.sh` and the files it sources) uses `set -u` only instead of `set -euo pipefail`, because a failing assertion must not abort the run.
- `make lint-shell` runs shellcheck (pinned image) over every `*.sh` outside hidden directories, `node_modules` and `.venv`, plus `tests/fixtures/action/docker`, at the default severity.
- `source` paths use a `# shellcheck source=<file>` directive relative to the script's directory (`--source-path=SCRIPTDIR`).
- Logs go to stderr. `wrapper.sh` and `install.sh` build the JSON lines with `printf`; the other scripts use `jq -cn`.
- Indent with what the file already uses: tabs in `pibox-entrypoint.sh` and `setup-provider-env.sh`, four spaces elsewhere.
