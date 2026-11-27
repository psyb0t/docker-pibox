# Docs and releases

- The documentation site is `docs/`, published by GitHub Pages from `main` at https://psyb0t.github.io/docker-pibox/ with Docusaurus (the project and its theme are in `website/`). Mode pages live in `docs/modes/` and keep their paths, because outside links point at them.
- A new page goes into `website/sidebars.mjs`, where nesting replaces the old `parent` field, and into `website/static/llms.txt`.
- Pages are plain Markdown, not MDX. Do not add Liquid tags or `raw` comments.
- After a docs change, run `make docs`. It builds the site into `website/build` and fails on a broken link or anchor.
- A behavior, setting or command change updates the matching docs page, `.env.example`, the skill (`.agents/skills/pibox/`) and the plugin README in the same change.
- Versions come only from `make version V=X.Y.Z`. CHANGELOG entries use the `## vX.Y.Z, YYYY-MM-DD` heading. A release is an annotated `vX.Y.Z` tag on a commit whose `main` pipeline run passed; the pipeline promotes that run's images and cuts the GitHub release.
