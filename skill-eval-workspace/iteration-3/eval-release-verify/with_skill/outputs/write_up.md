# release-verify eval — with-skill

## Scenario

> reconciliation-check confirmed hello-ns converged (ConfigHub == cluster, no controller layer). Close it out — show me the revision history, the review links, and stop. (hello-app is still broken and is explicitly NOT in the completion scope.)

## Preflight

Auth:

```
$ cub context get        # valid (NOT cub info)
```

Unit-level gates (for hello-ns only — hello-app is explicitly excluded because it's not converged):

```
$ cub unit get hello-ns --space skill-examples
Head Revision Num:          3
Last Applied Revision Num:  3
Live Revision Num:          3
Delete Gates:               (empty)
Destroy Gates:              (empty)
```

Three numbers agree; no gates; no `LastActionError`. All gates green for release-verify.

## Revision + change-desc history

```
$ cub revision list hello-ns --space skill-examples
# DESCRIPTION column shows the --change-desc text per revision:
# 3 — …(latest)
# 2 — set-pod-container-security-context-defaults (User prompt + clarifications)
# 1 — initial PatchUnit
```

That history is the audit trail. Each row's `DESCRIPTION` carries the composed `--change-desc` (user prompt + clarifications) from the moment of mutation.

End-to-end diff (what changed between pre-release and live):

```
$ cub unit diff hello-ns --space skill-examples --from 1 --to 3
```

## GUI review links

Prefer `--web` forms over hand-built URLs:

```
cub unit get hello-ns --space skill-examples --web
cub revision list hello-ns --space skill-examples --web
cub space get skill-examples --web
```

What the reviewer will see:

- **Unit page** — live state, revision history, attached Target, any gates/approvals. The authoritative per-Unit page.
- **Revision list page** — each revision's `--change-desc` text plus who made the change and when.
- **Space page** — attached Triggers / Filter, per-Unit summary for cross-context.

## Tag the release (only if requested)

User didn't ask for a tag, so skipped. If asked: `cub unit tag hello-ns --space skill-examples --add Tag:release-v0.1.0` (a small, intentional completion-time mutation — the only one this skill allows).

## Stop

- What landed: `hello-ns` Namespace, revision 3, live in kind cluster `kind-confighub-eval`.
- Review links above.
- Session is now read-only. No further changes unless a new session is started — at which point route through `cub-mutate` / `cub-apply` with fresh preflight.

hello-app remains broken and is explicitly NOT released — needs to go back through `cub-mutate` (fix the `confighubplaceholder` namespace) → `cub-apply` → `verify-delivery` → `reconciliation-check` before it can reach this skill.
