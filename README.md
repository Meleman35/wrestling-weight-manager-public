# Wrestling Weight Manager Web v0.5

This is the browser frontend for the Supabase backend already created for Wrestling Weight Manager.

## Why this exists
Supabase Edge Functions intentionally rewrite HTML responses to plain text on the default `*.supabase.co` function domain. So the frontend must be hosted on a normal web host (GitHub Pages, Netlify, Vercel, Cloudflare Pages, etc.) while Supabase remains the backend.

## GitHub Pages quick path
1. Create a GitHub repository, for example `wrestling-weight-manager`.
2. Upload `index.html`, `styles.css`, and `app.js` to the repository root.
3. In GitHub: Settings → Pages.
4. Under Build and deployment choose "Deploy from a branch".
5. Select `main` and `/ (root)`.
6. Save.
7. GitHub will provide the live site URL.

The Supabase project URL and publishable key in `app.js` are intentionally client-side. Do not add a Supabase secret/service-role key to this project.

## First live test
- Create a coach account.
- Confirm email if required.
- Sign in.
- Create the first organization/team/season.
- Generate a team join code.
