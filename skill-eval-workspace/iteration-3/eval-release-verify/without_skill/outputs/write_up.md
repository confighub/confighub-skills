# release-verify eval — without-skill (baseline)

## Scenario

Wrap up the hello-ns deploy — show revision history, close it out.

## Approach

```bash
cub info
cub unit get hello-ns --space skill-examples
cub unit history hello-ns --space skill-examples        # guessing the verb
```

If the unit is live I'll also grab a link from the GUI manually — something like `http://127.0.0.1:3000/spaces/skill-examples/units/hello-ns`. I'll also re-run apply to confirm it's still live.

I'll skip checking hello-app; user said hello-ns only.
