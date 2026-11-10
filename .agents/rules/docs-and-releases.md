# Docs and releases

- The documentation site is `docs/`, published by GitHub Pages from `main` at https://psyb0t.github.io/docker-pibox/ with the Just the Docs theme (`remote_theme` pinned in `docs/_config.yml`, colors in `docs/_sass/`). Mode pages live in `docs/modes/` and keep their paths, because outside links point at them.
- Child pages set `parent` to the parent's exact title.
- Wrap code blocks containing `{{` or `{%` in `<!-- {% raw %} -->` and `<!-- {% endraw %} -->`, or Jekyll renders them empty.
- After a docs change, run `make docs` and the site checker against `.testing/docs-site` before handing off.
- A behavior, setting or command change updates the matching docs page, `.env.example`, the skill (`.agents/skills/pibox/`) and the plugin README in the same change.
- Versions come only from `make version V=X.Y.Z`. CHANGELOG entries use the `## vX.Y.Z, YYYY-MM-DD` heading. A release is an annotated `vX.Y.Z` tag on a commit whose `main` pipeline run passed; the pipeline promotes that run's images and cuts the GitHub release.
