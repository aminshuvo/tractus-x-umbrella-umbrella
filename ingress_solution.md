# Discoveryfinder Ingress Regex PathType Problem & Solution

## Problem

When deploying the Tractus-X stack, the `discoveryfinder` component's ingress resource failed with the following error:

```
Error: UPGRADE FAILED: failed to create resource: admission webhook "validate.nginx.ingress.kubernetes.io" denied the request: ingress contains invalid paths: path /discoveryfinder(/|$)(.*) cannot be used with pathType Prefix
```

**Root Cause:**
- The ingress template for `discoveryfinder` used a regex path (`/discoveryfinder(/|$)(.*)`) with `pathType: Prefix`.
- Kubernetes (and NGINX ingress controller) does not allow regex paths with `Prefix` pathType. Regex paths require `ImplementationSpecific` pathType.
- The remote chart's template did not support overriding this behavior via values alone.

## Solution

### 1. Use ImplementationSpecific PathType
- The ingress template must use `pathType: ImplementationSpecific` when using a regex path.
- The correct configuration in the ingress template is:

```yaml
- path: {{printf "%s(/|$)(.*)" .Values.discoveryfinder.ingress.urlPrefix }}
  pathType: ImplementationSpecific
```

### 2. Use Proper Annotations
- The following ingress annotations must be set to support regex and proper path rewriting:

```yaml
nginx.ingress.kubernetes.io/rewrite-target: "/$2"
nginx.ingress.kubernetes.io/use-regex: "true"
```

### 3. Patch the Chart Locally
- Download the remote `discoveryfinder` chart and patch the ingress template as above.
- Use the patched chart as a local dependency in the umbrella chart's `Chart.yaml`:

```yaml
- condition: discoveryfinder.enabled
  name: discoveryfinder
  repository: file://charts/discoveryfinder
  version: 0.5.1
```

### 4. Update Values
- Ensure your values files (`helm/tractus-x-dev-values.yaml` and `charts/umbrella/values.yaml`) set the correct annotations and do not override the pathType.

### 5. Upgrade Helm Release
- Run `helm dependency update charts/umbrella/` and upgrade the release.
- The deployment will now succeed, as the ingress path and pathType are compatible.

## Why This Was Necessary
- The remote chart's template hardcoded the regex path with `Prefix` pathType, which is invalid.
- Overriding via values was not possible due to the template logic.
- Patching the template to use `ImplementationSpecific` allowed the deployment to succeed with the required routing behavior.

---

**In summary:**
- Regex paths in ingress require `ImplementationSpecific` pathType.
- Patch the chart template if the remote chart does not support this out of the box.
- Use the correct annotations for regex support in NGINX ingress. 