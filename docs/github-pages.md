# CardVault showcase website

The showcase is a static site served from `docs/`. It uses local fonts and images, has no third-party scripts or analytics, and needs no package installation or build step. The existing privacy policy stays at `privacy-policy.html`.

## Preview locally

From the repository root:

```bash
python3 -m http.server 8080 --directory docs
```

Open <http://localhost:8080>. Check the mobile layout, screenshot gallery, keyboard navigation, and FAQ before publishing.

## Publish on GitHub Pages

1. Commit and push the website and its assets to the branch you want to publish, normally the default branch. Include the `docs/images/` screenshots added with the README.
2. Open the repository's **Settings → Pages**.
3. Under **Build and deployment**, choose **Deploy from a branch**.
4. Select that branch and the **/docs** folder, then save.

GitHub publishes the site at <https://gauravagarwal2704.github.io/cards-vault/> once deployment completes. If Pages already publishes `/docs` from this branch, pushing the files updates the site automatically. No separate deployment workflow is required.

Reference: [GitHub's publishing-source documentation](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site).

## Edit the site

- `index.html`: copy, metadata, links, screenshot order, and FAQs.
- `assets/site.css`: responsive layouts, colors, and local font definitions.
- `assets/site.js`: progressive enhancements for gallery controls and screenshot previews. Links, FAQs, and the gallery remain usable without JavaScript.
- `images/`: Google Play screenshots shared with the repository README.
- `assets/app-icon-rose.png`: flat rose-colored website icon, adapted from the app branding with imagegen. The original icon remains in `assets/app-icon.webp`.
- `assets/fonts/`: Outfit fonts, copied from the app's font assets. See `assets/fonts/OFL.txt` for their license.

Keep product and security descriptions aligned with the app. Update the canonical and social URLs if the GitHub owner, repository name, or domain changes. This website does not change the Flutter app version.
