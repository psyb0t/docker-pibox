# GitHub Action

[Back to README](../README.md)

The root [`action.yml`](../action.yml) runs Pi through this repository's wrapper. It mounts context read-only at `/context`, uses a separate writable output directory, and creates fresh Pi, runtime, and SSH state for each invocation.

```yaml
jobs:
  summarize:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
        with:
          persist-credentials: false
      - id: pi
        uses: psyb0t/docker-pibox@main
        with:
          prompt: "Read /context/CHANGELOG.md and write summary.md."
          provider-api: anthropic-messages
          provider-base-url: https://api.z.ai/api/anthropic
          provider-api-key: ${{ secrets.PI_PROVIDER_API_KEY }}
          model: your-model-id
      - name: Read the result
        env:
          OUTPUT_PATH: ${{ steps.pi.outputs.output-path }}
        run: cat "$OUTPUT_PATH/summary.md"
```

## Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `prompt` / `prompt-file` | | Set exactly one nonempty prompt. File paths resolve relative to the checked-out workspace unless absolute. The complete prompt must fit within 100,000 UTF-8 bytes. |
| `context-path` | `.` | Existing context directory mounted at `/context:ro`. |
| `output-path` | unique directory under `$RUNNER_TEMP` | Writable workspace for requested files. Neither context nor output may contain the other. Mount paths cannot contain colons, commas, or newlines. |
| `provider-api-key` | required | Upstream API key or token, passed from GitHub secrets. |
| `provider-base-url` | required | HTTP base URL with its API prefix. |
| `provider-api` | `openai-completions` | Also accepts `openai-responses`, `anthropic-messages`, or `google-generative-ai`. See [providers](providers.md). |
| `model` | required | Upstream model ID. |
| `thinking` | Pi default | `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, or `max`, subject to model support. |
| `image` | `psyb0t/pibox:latest` | Minimal image. Use `psyb0t/pibox:latest-full` for the shared development toolchain. |
| `stream` | `true` | With `output-format: json`, print readable live assistant messages, tool calls, and tool results. `false` keeps the same final result without these logs. |
| `output-format` | `json` | `json`, `text`, or `stream-json`. |

## Outputs and failure handling

`output-path` is the absolute generated-file directory. `result` contains the final assistant text for `json`, or native stdout for `text` and `stream-json`, with trailing newlines trimmed. Use artifacts for large responses and generated files instead of putting them in action outputs.

Pi's native JSON mode is NDJSON. The action's `json` option collects that event stream and extracts the final assistant from `agent_end.messages`. It does not apply a JSON schema to the model's response. `stream-json` returns native events unchanged; it does not print readable live activity to the job log. The full native stdout and action log remain in the invocation's `pibox-action.*` directory under `$RUNNER_TEMP`.

Image pull failures and nonzero CLI exits fail the step. JSON modes also fail on malformed events, missing completion, missing final assistant, or an error, aborted, or incomplete final turn. Text mode follows the CLI's exit status. Tool calls in a successful run may still include recoverable tool errors.

## Runner trust

Use this action only on trusted workloads on disposable runners. The wrapper mounts the host Docker socket, uses host networking, and runs Pi with passwordless sudo. Docker socket access gives the agent control over the runner; the context's read-only mount and prompt instructions are not a security sandbox.

Keep `contents: read`, disable persisted checkout credentials, and give the job no unrelated secrets. The action forwards only its explicit provider settings and fresh state paths. It does not mount the host's Pi auth, SSH agent, or sibling wrappers. Model output is untrusted, including generated files; do not execute or interpolate it into shell source without validation. The action disables GitHub workflow-command interpretation while logging agent output.
