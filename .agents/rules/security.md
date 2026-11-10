# Security

- The wrapper gives the container the host Docker socket, host networking and the user's workspace. Do not widen what it mounts or forwards without documenting it in `docs/security.md` and `docs/install.md`.
- Only `PIBOX_*` variables, minus the wrapper's own settings, cross into the container. Keep the wrapper's skip list complete when adding a host-side setting, so it is not leaked into the container environment.
- With `PIBOX_PROVIDER_*`, the key reaches Pi only as `OPENAI_API_KEY`; `models.json` stores the `$OPENAI_API_KEY` reference. Keep secrets out of `pibox-provider.json`, logs and argv.
- `setup-provider-env.sh` refuses symlinked `models.json` and `pibox-provider.json` and writes both with mode `600`. Keep the checks when touching the file handling.
- The GitHub Action masks the key with `::add-mask::` before logging starts, stops workflow-command interpretation while Pi output is printed, mounts context read-only and uses fresh state per run. Keep all four.
- Empty `PIBOX_API_MODE_TOKEN` or `PIBOX_MCP_MODE_TOKEN` means no auth, and Telegram with no allowlist answers every chat. Examples in docs, the skill and the plugin must set tokens and allowlists.
- Existing input bounds: prompt size in the action (`MAX_PROMPT_BYTES`), lengths and single-line checks in the bootstrap, the marker size in the adapter.
