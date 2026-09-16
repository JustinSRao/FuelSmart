# Security audit — FuelSmart 1.0 (Java prototype) → 2.0

Audit date: 15 September 2026
Audited artefact: `FuelSmart-main.zip` (GitHub default-branch export, committed 28 December 2024)

## Summary

| | |
|---|---|
| Secrets found | **1** — an OpenAI API key, hard-coded |
| Occurrences in the archive | **2 source occurrences + 1 compiled artefact** |
| Status in FuelSmart 2.0 | Not carried over. The new application requires **zero** secret API keys. |
| Status of the exposed key | **Resolved — revoked by OpenAI's automated secret scanning** (owner notified by email, September 2026). |
| Action outstanding | None urgent. History purge is now optional hygiene. |

> **What the automatic revocation tells us.** OpenAI revokes keys that its
> scanners find in **public** repositories. The revocation email therefore
> confirms the repository was public and the key was scraped by an automated
> crawler before it was disabled. The key is dead, so there is no further
> billing exposure; reviewing the account's usage history for calls the owner
> did not make is the only remaining check. The history purge below is retained
> for reference but is no longer time-sensitive.

---

## Finding 1 — Hard-coded OpenAI API key (critical)

**Location**

| File | Detail |
|---|---|
| `src/main/java/fuelsmart/CarDataFetcher.java` | line ~16, inside `chatGPT1(...)` |
| `src/main/java/fuelsmart/CarDataFetcher.java` | line ~68, inside `chatGPT2(...)` — the *same* key, duplicated |
| `build/classes/java/main/fuelsmart/CarDataFetcher.class` | the key is compiled into the string constant pool |

The literal is a project-scoped OpenAI key (an `sk-proj-` prefixed token; the value is deliberately not reproduced here). It is assigned to a local `String apiKey` and sent as `Authorization: Bearer …`.

**Why this is critical**

- `.gitignore` in the prototype is a **zero-byte file**, so `build/` and `.gradle/` were committed. The key therefore exists in the repository *twice*: in readable source and inside a compiled `.class` binary. Scrubbing only the `.java` file would leave the key recoverable with `strings` on the class file.
- The archive is named `FuelSmart-main`, the shape GitHub produces for a default-branch download. If that repository is or ever was public, the key must be treated as disclosed to the internet. Automated scrapers harvest `sk-` patterns from public GitHub within minutes.
- A leaked OpenAI key is a direct billing liability: it can be used until revoked.

### Remediation

1. ~~**Revoke the key.**~~ **Done** — revoked by OpenAI automatically.
2. **Check usage** on the OpenAI dashboard for calls you did not make. This is the one check still worth performing.
3. *Optional now that the key is dead:* **purge the history**, or replace the repository. The key is present in source *and* build output, so a single-file fix would not have been enough:

   ```bash
   # Preferred: git-filter-repo (faster and safer than filter-branch)
   pip install git-filter-repo

   git clone --mirror https://github.com/<you>/FuelSmart.git
   cd FuelSmart.git

   # Remove the committed build output and the Gradle cache entirely
   git filter-repo --path build/ --path .gradle/ --path .idea/ --invert-paths

   # Redact the literal wherever it still appears in tracked text
   # Write the key literal into redact.txt yourself; it is deliberately
   # not reproduced anywhere in this repository.
   printf 'literal:<THE-LEAKED-KEY>==>REDACTED-REVOKED-OPENAI-KEY
' > ../redact.txt
   git filter-repo --replace-text ../redact.txt

   git push --force --all
   git push --force --tags
   ```

   Rewriting history does **not** remove the blobs from existing forks, clones, or GitHub's cached views. If the repository was public, treat revocation as the real fix and consider deleting and recreating the repository instead.
4. **Ask GitHub to expire cached views** of the affected commits if the repository was public (GitHub Support can purge the cached blob pages).
5. **Never commit a replacement.** FuelSmart 2.0 needs no key at all — see below.

> The full literal is **deliberately not reproduced anywhere in this repository**. Only a truncated prefix appears above, enough to identify the finding. An earlier draft of this document quoted the key in full so the redaction command could be copy-pasted; that was removed, because once the history purge succeeded this document became the last remaining copy — which would have defeated the exercise.

---

## Finding 2 — Fabricated vehicle data presented as fact (design flaw)

Not a secret, but the reason the prototype's numbers could not be trusted.

`CarDataFetcher` asked `gpt-3.5-turbo` to return *"the price in USD, the fuel tank size in gallons, and the miles per gallon"* as three bare numbers, then parsed them with a regex and used them for financial arithmetic. A language model does not know a vehicle's price or its EPA rating; it produces a plausible-looking number. Every downstream figure inherited that.

**Resolved in 2.0.** Efficiency comes from Natural Resources Canada and the U.S. DOE/EPA, bundled and verifiable. Price is never guessed — the user is asked what they will actually pay. No model is consulted for any number.

## Finding 3 — Hard-coded currency conversion (correctness)

`GasCar` and `ElectricCar` each hard-coded `double exchangeRate = 1.44` to convert USD to CAD. A rate frozen in December 2024 silently skews every Canadian result thereafter.

**Resolved in 2.0.** Regions are separate and self-contained: a Canadian comparison is entered and displayed wholly in CAD, a U.S. one wholly in USD. FuelSmart performs no currency conversion, so there is no rate to go stale and no dependency on an FX service.

## Finding 4 — Result biased toward one powertrain (neutrality)

`FuelSmart.main` concluded *"For a cheaper (short and long term), and more fuel-efficient vehicle, you should buy the [electric car]"* whenever the electric vehicle's price was lower or equal, and computed a break-even distance only in the remaining branch. Running costs were derived from tank size × price ÷ (MPG × tank gallons) — i.e. cost per mile — while ignoring insurance, maintenance, financing and incentives entirely.

**Resolved in 2.0.** The engine makes no assumption about which side is electric, cheaper, or destined to catch up; all five possible outcomes (including "no break-even exists") are first-class results, and the app states costs rather than recommending a purchase.

---

## FuelSmart 2.0 secret posture

| | |
|---|---|
| Secret API keys required | **None** |
| Credentials stored in the app | **None** |
| Network calls at rest | **None** |
| Optional network calls | NHTSA vPIC VIN decode (no key); government dataset refresh (no key) |
| Backend operated by us | **None** |
| Recurring infrastructure cost | **$0** |

Both optional endpoints are unauthenticated public government services. Neither is required for any core feature: the vehicle database is bundled, and comparison, charts, saving, export and settings all work with the network off.

### Verifying the tree stays clean

```bash
# Should return nothing.
grep -rInE "sk-[A-Za-z0-9_-]{16,}|api[_-]?key|secret|bearer |password|token" \
  --include='*.swift' --include='*.py' --include='*.json' --include='*.plist' .
```

`.gitignore` now excludes build output, derived data and the raw `DataSources/` downloads, so no compiled artefact can carry a string into a commit the way `CarDataFetcher.class` did.
