# GitHub Pages

Workflow: `.github/workflows/pages.yml` — on push to `main`, exports Godot **Web** (preset name `Web`) and deploys to Pages.

Enable once: repo **Settings → Pages → Source = GitHub Actions**.

Until a Web export preset exists in the project, the workflow publishes a small HTML stub so the site is non-empty.
