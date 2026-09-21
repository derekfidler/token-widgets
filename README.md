# Token Widgets

A macOS desktop widget showing your current Claude and ChatGPT/Codex usage — either
personal-plan rate-limit bars (5-hour / weekly, like claude.ai's usage panel) or
enterprise/team dollar spend — so you don't have to log in to either site to check.

## How it's built

- **`TokenWidgetsApp`** — a menu-bar-only helper app (no Dock icon). It holds your
  credentials (macOS Keychain), fetches usage on a timer, and writes the result to a
  shared App Group cache.
- **`TokenWidgetsWidgetExtension`** — the actual desktop widget (WidgetKit). It only
  ever reads that shared cache; it never makes network calls itself.

Two independent data paths per product, chosen by which credentials you provide:

| Mode | Source | Credential |
|---|---|---|
| Claude personal | reverse-engineered claude.ai endpoint | session cookie |
| Claude enterprise | official [Analytics API](https://platform.claude.com/docs/en/api/admin/analytics) | Analytics API key |
| ChatGPT/Codex personal | reverse-engineered chatgpt.com endpoint (same one Codex CLI uses) | session cookie |
| ChatGPT/Codex enterprise | official [Costs API](https://platform.openai.com/docs/api-reference/usage/costs_object) | Admin API key |

## First-time setup

1. Open `TokenWidgets.xcodeproj` in Xcode.
2. Select the **TokenWidgetsApp** target → Signing & Capabilities → set **Team** to your
   own (free) Apple ID team. Repeat for the **TokenWidgetsWidgetExtension** target — both
   must use the same team so the App Group entitlement (`ESYNZ5PVA4.dev.flatpay.tokenwidgets`)
   resolves consistently.
3. Build & run the **TokenWidgetsApp** scheme (⌘R). A gauge icon appears in the menu bar;
   there's no Dock icon by design.
4. Click the menu bar icon → **Settings…**. For each product, pick **Personal** or
   **Enterprise** and either:
   - **Personal**: click **Log in to claude.ai…** / **Log in to chatgpt.com…** and sign in
     normally in the embedded window — the session cookie is captured automatically and
     stored in Keychain. (A manual paste field is also there as a fallback.)
   - **Enterprise**: paste an API key.
     - Claude: Claude Console → Settings → Analytics API keys (Claude Enterprise only).
     - ChatGPT: platform.openai.com → Organization → Admin keys.
5. Click **Refresh Now** in the menu bar dropdown to confirm data loads.
6. Add the widget to your desktop: right-click the desktop → **Edit Widgets** (or press
   the widget-gallery key), find **Token Usage**, and drag it out.

The app registers itself as a login item on first launch, so it starts automatically.
You can change that later in **Settings → General**.

## Development and QA

The Xcode project is generated from `project.yml`; edit the YAML rather than making
structural target changes only in Xcode. To regenerate the project, run the unit tests,
and perform a Release static-analysis build:

```sh
./scripts/qa.sh
```

This requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The test suite
uses representative fixtures for all four provider response paths and verifies that
diagnostic errors cannot persist response-body secrets.

## If Claude's personal usage doesn't load

The Claude personal fetch path (`ClaudePersonalFetcher.swift`) hits an internal claude.ai
endpoint that isn't documented anywhere — the URL in the code is a best-effort guess based
on the known response shape (`raw_limits.five_hour` / `raw_limits.seven_day`), not a
confirmed path. If it 404s or the error in Settings says so:

1. Open claude.ai/settings/usage in a browser while logged in, open DevTools → Network,
   filter to Fetch/XHR, and reload.
2. Find the request whose response contains `five_hour`/`seven_day` fields.
3. Copy its path (everything after `claude.ai`) and paste it into **Usage endpoint
   override** in Settings → Claude.

The ChatGPT/Codex personal path is more solid — it's the same `backend-api/wham/usage`
endpoint Codex CLI itself uses — but could still change without notice since it's also
unofficial.

## Security notes

- All credentials (session cookies, API keys) live only in the macOS Keychain, scoped to
  this app. The widget extension never has access to them — it only reads the computed,
  non-secret usage numbers from the shared App Group cache.
- Session-cookie based fetching uses undocumented endpoints. It's for personal use against
  your own account and could break if either site changes its frontend.
