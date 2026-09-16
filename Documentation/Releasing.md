# Getting FuelSmart onto TestFlight

## The thing to understand first

**TestFlight does not skip the build.** An upload begins with `xcodebuild
archive`, which compiles every line of Swift in the project. It is a *superset*
of a local build, not an alternative to one, and it additionally needs code
signing, a registered bundle id, and an App Store Connect app record.

Since this repository's Swift has never been compiled, the first archive attempt
will surface whatever compile errors exist — just 20 minutes and one build number
later than a plain build would have. So:

```
CI (compile + test)  →  fix what it finds  →  TestFlight
```

The `CI` workflow exists precisely so that loop is fast.

---

## Path A — you have access to a Mac

Fastest signal, in order of cost:

```bash
# 1. The whole financial model. ~2 minutes, no Xcode project needed.
cd Packages/FuelSmartCore && swift test

# 2. The app compiles, both platforms.
brew install xcodegen
xcodegen generate
xcodebuild build -scheme FuelSmart -destination 'platform=iOS Simulator,name=iPhone 16'

# 3. Then archive from Xcode, or let the workflow do it.
```

Step 1 is the one worth doing first. It exercises every calculation with no
signing, no simulator and no project file, so it isolates "is the engine sound"
from "is the SwiftUI wiring right".

## Path B — no Mac

Both workflows run on GitHub's macOS runners, so you never touch a Mac:

1. Push the repository to GitHub.
2. **Actions → CI → Run workflow.** This compiles the core package, runs its
   tests, builds the app for iOS and macOS, and runs the UI tests.
3. Fix whatever it reports, push, repeat until green.
4. Complete the one-time App Store Connect setup below.
5. **Actions → TestFlight → Run workflow**, with a build number.

### Cost, honestly

The app itself has no recurring cost, and that is unchanged. CI is a different
budget:

| Repository | macOS runner cost |
|---|---|
| **Public** | Free, unlimited |
| **Private** | Billed against included minutes at a **10× multiplier** |

On the GitHub Free plan, 2,000 included minutes per month becomes roughly **200
minutes of macOS time**. A full CI run here is about 20–30 macOS minutes and a
TestFlight archive about 20, so a private repo gets a handful of runs a month
before it starts costing real money.

Two ways to stay at zero:

- **Make the repository public.** Do the history purge in
  [`SecurityAudit.md`](SecurityAudit.md) first — the old prototype's leaked key is
  revoked, but there is no reason to publish it.
- **Borrow a Mac once.** Only the first compile pass is painful; after that CI
  runs are short.

---

## One-time App Store Connect setup

1. **Register the bundle id.** Developer portal → Identifiers → `com.fuelsmart.app`.
2. **Create the app record.** App Store Connect → Apps → New App, same bundle id.
3. **Create an API key.** Users and Access → Integrations → App Store Connect
   API → team key with the **App Manager** role. The `.p8` downloads **once**.
4. **Add three repository secrets** (Settings → Secrets and variables → Actions):

   | Secret | Value |
   |---|---|
   | `ASC_KEY_ID` | the key's 10-character id |
   | `ASC_ISSUER_ID` | the issuer UUID above the key list |
   | `ASC_KEY_P8` | the whole `.p8` file, `BEGIN`/`END` lines included |

5. **Set `TEAM_ID`** at the top of `.github/workflows/testflight.yml`.

> These are your credentials for talking to Apple, held in GitHub's encrypted
> secret store. They are never committed, and they are not part of the app — the
> shipped product still contains **zero** API keys, which is what the security
> requirement was about. The workflow deletes the key from the runner in a step
> that runs even on failure.

Signing itself needs no manual certificate wrangling: `-allowProvisioningUpdates`
plus the API key lets Xcode create and download what it needs.

---

## Answers you will be asked

Both are trivial for this app, and both are already backed by the privacy
manifest in `Info.plist`:

| Question | Answer | Why |
|---|---|---|
| Export compliance / encryption | **No** | FuelSmart uses no encryption beyond standard HTTPS to two public government endpoints. |
| Does the app collect data? | **No** | No account, no analytics, no tracking SDKs. `NSPrivacyCollectedDataTypes` is empty and `NSPrivacyTracking` is false. |
| Does it track users? | **No** | Nothing leaves the device except what the user deliberately shares. |

For the tester notes, something like:

> FuelSmart compares what two vehicles will actually cost to own. Pick any two
> from the bundled government efficiency data, enter what you'd really pay, and it
> charts both costs over time to find the crossover — if there is one. Everything
> works offline; there's no account.
>
> Worth poking at: the break-even cases where there *isn't* a crossover, the
> Scenario Lab sliders, keep-vs-replace (the owned car's price is sunk and must
> never be charged), and the PDF export.

---

## Build numbers

`CURRENT_PROJECT_VERSION` is passed in at archive time, so the workflow input is
the single source of truth. It must strictly increase — App Store Connect rejects
a build number it has already seen, for a given version string.

`MARKETING_VERSION` (2.0) lives in `project.yml` and only changes for a release.

---

## Known gaps before a wider TestFlight

These do not block an internal build, but are worth knowing:

- **The Swift has never compiled.** Everything above assumes that pass happens
  first.
- **No launch screen storyboard.** `UILaunchScreen` is an empty dict, which gives
  a plain background — acceptable, not polished.
- **The macOS build is unsigned for distribution.** The workflow archives for
  iOS; a Mac TestFlight build needs its own archive step and a macOS app record.
- **No localisation.** Strings are English, and formatting is region-aware
  (en-CA / en-US) rather than fully localised.
