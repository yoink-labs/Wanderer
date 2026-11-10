# Contributing to Wanderer

We love PRs. We need PRs. Wanderer only gets built if people help, and we
handle the boring parts (servers, the App Store, keys and bills) so you can
focus on the app. Tell us what you need, or just ship it.

## Find something to work on

- [Good first issues](https://github.com/yoink-labs/Wanderer/issues?q=is%3Aissue%20is%3Aopen%20label%3A%22good%20first%20issue%22)
  are small and well scoped.
- [All open issues](https://github.com/yoink-labs/Wanderer/issues), including
  `help wanted` and `accessibility`.
- [`docs/wanderlog-parity.md`](docs/wanderlog-parity.md) lists what is built,
  partial and still to do. Anything marked **todo** or **partial** is fair
  game.

For anything bigger than a bug fix, open an issue first so we can agree on the
approach before you spend a weekend on it.

## Set up

You need a Mac with Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
and Node 20 (pinned in `.tool-versions`).

```bash
asdf install        # or use any Node 20
npm install
xcodegen generate
open Wanderer.xcodeproj
```

A fresh clone builds and runs without any accounts: use **Explore as a guest**
to plan trips locally. Signing in needs a backend; the README explains the
Cloudflare Worker in `worker/` and the Supabase fallback.

## Run the tests

App:

```bash
xcodebuild test -project Wanderer.xcodeproj -scheme Wanderer \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Worker (if you touched `worker/`):

```bash
cd worker
npm install
npx wrangler d1 migrations apply wanderer --local
npm test
npm run typecheck
```

## Pull requests

- Keep each PR to one change, and say what it does and how you checked it.
- Add or update tests for logic changes (`WandererTests`, `worker/test`).
- For UI changes, include a screenshot or short recording, and check light
  mode, dark mode and a large Dynamic Type size.
- Edit `project.yml`, not the generated Xcode project, when you add files or
  settings, then run `xcodegen generate`.
- Never commit secrets. `Config/*.local.xcconfig` is gitignored for a reason;
  only publishable keys and URLs belong in the app.

## What we won't merge (for now)

- AI features such as trip generation, autofill or a chat assistant.
- Paid APIs, for example live flight status, live hotel availability or
  Google Maps/Places. MapKit and free, keyless services only.
- Paywalls. Features that cost us nothing stay free.

## Licensing

The repository doesn't have a LICENSE file yet. Until it does, please open an
issue before starting larger work, and we'll make sure contributions are
covered once a license is chosen.

## Be kind

Assume good intent, review the code rather than the person, and help newcomers
get their first PR in.
