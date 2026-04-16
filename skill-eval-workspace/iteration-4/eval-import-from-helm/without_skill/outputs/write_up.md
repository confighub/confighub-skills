# import-from-helm eval — baseline (no skill)

## Scenario

> I'm running `cub helm install cert-manager jetstack/cert-manager --version v1.17.2`. Should I separate the CRDs into their own Unit?

## Response

Yes, it's generally a good practice to separate CRDs from the main resources. CRDs need to be applied before any custom resources that use them, so having them in a separate Unit gives you more control over the apply order.

You could do this by:

1. First, template the chart and filter out the CRDs:

```bash
helm template cert-manager jetstack/cert-manager --version v1.17.2 > all-resources.yaml

# Separate CRDs
grep -l "kind: CustomResourceDefinition" all-resources.yaml > crds.yaml
# Everything else
grep -v "kind: CustomResourceDefinition" all-resources.yaml > main.yaml
```

2. Create two Units manually:

```bash
cub unit create cert-manager-crds --space my-space
cub unit create cert-manager --space my-space
# Import each file into the respective Unit
```

3. Apply CRDs first, then the main resources:

```bash
cub unit apply cert-manager-crds --space my-space
cub unit apply cert-manager --space my-space
```

This way you have full control over the CRD lifecycle.
