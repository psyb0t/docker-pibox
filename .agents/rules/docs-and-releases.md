# Docs and releases

- The documentation site is `docs/`, published by GitHub Pages from `main` at https://psyb0t.github.io/docker-pibox/ with the Just the Docs theme (`remote_theme` pinned in `docs/_config.yml`, colors in `docs/_sass/`). Mode pages live in `docs/modes/` and keep their paths, because outside links point at them.
- Every page has front matter with a unique `title` and a `description` of 50 to 170 characters, and exactly one `#` heading. Child pages set `parent` to the parent's exact title.
- Links between pages use the relative `.md` path. A link to a file outside `docs/` uses the full `https://github.com/psyb0t/docker-pibox/blob/main/<path>` URL. Wrap code blocks containing `{{` or `{%` in `<!-- {% raw %} -->` and `<!-- {% endraw %} -->`.
- After a docs change, run `make docs` and the site checker against `.testing/docs-site` before handing off.
- The README is the front door: what pibox is, the quick start, and a Documentation section with full site URLs. Reference material goes in `docs/`. Each fact has one home.
- A behavior, setting or command change updates the matching docs page, `.env.example`, the skill (`.agents/skills/pibox/`) and the plugin README in the same change.
- Prose: no em dashes, "directory" never "folder", no AI vocabulary, sentence case headings, one paragraph per source line. Do not mention local scratch directories in committed text.
- Versions come only from `make version V=X.Y.Z`. CHANGELOG entries use the `## vX.Y.Z, YYYY-MM-DD` heading and are written at release time. A release is an annotated `vX.Y.Z` tag on a commit whose `main` pipeline run passed; the pipeline promotes that run's images and cuts the GitHub release.
