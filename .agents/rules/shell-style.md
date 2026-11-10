# Shell style

Applies to `wrapper.sh`, `install.sh`, `pibox-entrypoint.sh`, `pibox/scripts/*.sh`, `pibox/init.d/*.sh`, `scripts/github-action.sh`, `test.sh` and `tests/*.sh`.

- Start with `#!/bin/bash` or `#!/usr/bin/env bash`, then `set -euo pipefail`. The e2e suite (`test.sh`, `tests/common.sh` and the files it sources) uses `set -u` only, because a failing assertion must not abort the run.
- `make lint-shell` runs shellcheck (pinned image) over every `*.sh` outside hidden directories, `node_modules` and `.venv`, plus `tests/fixtures/action/docker`. It must stay clean at the default severity. Fix the code; add a `# shellcheck disable=SCxxxx` only with a reason on the same or the previous line.
- `source` paths use a `# shellcheck source=<file>` directive relative to the script's directory (`--source-path=SCRIPTDIR`).
- Name constants with `readonly` at the top of the file, as `setup-provider-env.sh` and `scripts/github-action.sh` do. No magic numbers in the body.
- Validate every input from the environment before use: `case` over the allowed values, regex checks, length limits, and a single-line check for anything that ends up in a file or a Docker argument. Error text names the variable and the allowed values.
- Log as one JSON object per line on stderr with `time`, `level`, `file`, `line`, `func` and `msg`. `wrapper.sh` and `install.sh` use `printf`; the other scripts use `jq -cn`. Never log secrets.
- Write files atomically: `mktemp` in the target directory, `chmod`, then `mv`. Refuse symlinked targets where a file holds configuration, as `write_provider` does.
- Unused loop variables are `_`. Indent with what the file already uses (tabs in `pibox-entrypoint.sh` and `setup-provider-env.sh`, four spaces elsewhere).
