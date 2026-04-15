# Where is checkout v0.4.2 deployed?

## Response to user

**There is no `checkout` unit and no image tagged `v0.4.2` on your local ConfigHub instance.**

I queried across all Spaces using the `cub-query` skill patterns — by Unit slug, by DisplayName, by image tag `:v0.4.2`, and by image URI containing `checkout`. All four queries returned zero rows.

For context, your local instance currently has 4 Spaces (`default`, `test-space`, `platform`, `skill-examples`) and only 2 Units total, both in `skill-examples`:

- `hello-app` (a Deployment-ish unit)
- `hello-ns` (a Namespace)

Neither is a `checkout` service. So the release you're asking about isn't tracked in this ConfigHub instance at all — it may live in a different instance, or the service may simply not be onboarded here yet.

If you expected `checkout` to be here, worth checking:
- Are you pointed at the right ConfigHub instance? (`cub context get`)
- Is it onboarded under a different slug? I can re-run with a different name.

## Commands run + outputs

### 1. Exact slug match

```bash
cub unit list --space "*" --where "Slug = 'checkout'"
```
```
NAME    SPACE    CHANGESET    TARGET    STATUS    LAST-ACTION    RESOURCE-STATUS    UPGRADE-NEEDED    UNAPPLIED-CHANGES    APPLY-GATES    LAST-CHANGE-DESCRIPTION
```
(zero rows)

### 2. Slug prefix match

```bash
cub unit list --space "*" --where "Slug LIKE 'checkout%'"
```
(zero rows)

### 3. DisplayName contains

```bash
cub unit list --space "*" --where "DisplayName LIKE '%checkout%'"
```
(zero rows)

### 4. Content query for image tag v0.4.2

```bash
cub unit list --space "*" --where-data "spec.template.spec.containers.*.image#reference = ':v0.4.2'"
```
(zero rows)

### 5. Content query for image URI containing checkout

```bash
cub unit list --space "*" --where-data "spec.template.spec.containers.*.image ~ 'checkout'"
```
(zero rows)

### 6. Sanity check — what's actually here

```bash
cub space list
```
```
NAME              #UNITS
default           0
test-space        0
platform          0
skill-examples    2
```

```bash
cub unit list --space "*"
```
Returns only `hello-app` and `hello-ns`, both in `skill-examples`. No `checkout` service.

## Reasoning / strategy notes

The skill prescribes two complementary query dimensions:

- **Metadata** (`--where` on `Slug`, `DisplayName`, etc.) — catches Units named after the service.
- **Content** (`--where-data` on path expressions into the resource body) — catches Units whose image reference matches the release, regardless of how they're named.

I ran both, because "where is release X deployed" can legitimately resolve either way — a Unit named `checkout` in several per-env Spaces, or a generic Unit whose container image points at `checkout:v0.4.2`. Zero hits on either dimension, combined with only 2 Units total on the instance, makes the negative answer conclusive rather than a false negative from a narrow filter.

I deliberately did not fabricate a list of environments — per the Reality Rule, an empty result is the finding.
