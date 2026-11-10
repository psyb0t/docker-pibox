# Testing

- `make test-ci` is what CI runs and must stay offline and credential-free: `test-python`, `test-wrapper-install`, `test-action`, `test-entrypoint-identity`, `test-action-provider-output` and `test-openclaw-bridge`. It may pull images, nothing else from the network.
- `make test` is the e2e suite. It builds `pibox:local`, needs `.env.test` (copy `.env.test.example`) and a real LLM endpoint, and never runs in CI. Run it for changes to the adapter, the entrypoint, the provider bootstrap, the Dockerfiles or the Pi version.
- A new e2e test is a `test_*` function in a `tests/test_*.sh` file, registered in `ALL_TESTS`; `test.sh` sources every such file except the standalone ones it skips. Register every container a test starts so `test_teardown` removes only that run's containers.
- Standalone contract tests (`tests/test_wrapper_install.sh`, `tests/test_github_action.sh`, `tests/test_entrypoint_identity.sh`, `tests/action-provider-output.sh`, `tests/test_openclaw_bridge.sh`) run on their own with stubs or the base image. Use stub commands on `PATH` (as `tests/fixtures/action/docker` does) rather than real Docker or network calls when the behavior under test is the script.
- Test data uses placeholders such as `EXAMPLE-DO-NOT-USE`, `example.invalid` and `example-model`.
- Adapter changes get a pytest case in `pibox/tests/`. Run it with `make test-python`.
