# Runbook: Resolving "Unrecognized key: accountsSvcUrl" and Project Move (Clawdbot → OpenClaw)

## 📋 Problem Description
When running CLI commands, the application fails with a configuration validation error:
`Invalid config: gateway.auth: Unrecognized key: "accountsSvcUrl"`

This occurs when:
1.  **Version Mismatch:** Your `clawdbot.json` contains newer fields than your installed binary recognizes.
2.  **Stale Global Binary:** You updated the source code, but the global `clawdbot` command still points to an old version (e.g., `2026.1.24`).
3.  **Project Rename:** The project has moved from `clawdbot` to **OpenClaw**. The new global command is `openclaw`.

---

## 🔍 Diagnostics

Check which version is being executed by your shell:
```bash
clawdbot --version
# If it shows 2026.1.24-3 or similar, it is STALE.

# Check the direct entry point in your source directory:
node ~/openclawbot.svc.plus/openclaw.mjs --version
# This should show 2026.1.29 or later.
```

Find where the stale binary is located:
```bash
which -a clawdbot
# Example: /usr/local/lib/npm/bin/clawdbot
```

---

## 🛠️ Resolution Steps

### Step 1: Update Source & Rebuild
Ensure your local source is on the correct branch and built:

```bash
cd ~/openclawbot.svc.plus
git fetch origin
git checkout feat/console-auth-nodes
git pull origin feat/console-auth-nodes

pnpm install
pnpm build
```

### Step 2: Install the NEW Global Command
The project is now **OpenClaw**. Running `npm install -g .` will install the `openclaw` command.

```bash
cd ~/openclawbot.svc.plus
npm install -g .
```

### Step 3: Restore 'clawdbot' Command (Optional)
If you want to continue using the name `clawdbot`, link it to the new `openclaw` binary:

```bash
# Force symlink the old name to the new version
ln -sf $(which openclaw) $(which clawdbot)
```

### Step 4: Re-install Daemon Service
Once the binary is updated, re-run the onboarding to update the background service:

```bash
openclaw onboard --install-daemon --accept-risk
```

---

## ✅ Verification
Running either command should now show the correct version and pass validation:
```bash
openclaw --version 
# Output: 2026.1.29

clawdbot gateway status
# Should show "RPC probe: ok" without schema errors
```

---

## ⚠️ Pre-requisites for Source Build
If building from source (as in Option A), ensure your environment has:
- **Node.js**: v22.12.0+ (v24 recommended)
- **PNPM**: Installed and configured
- **Permissions**: If running as root, ensure `git` and `pnpm` are accessible.

---

## ✅ Verification
After updating, running the command should show the new version banner:
`🦞 OpenClaw 2026.1.29`

Validation will pass because `src/config/zod-schema.ts` now defines:
```typescript
auth: z.object({
  // ...
  accountsSvcUrl: z.string().url().optional(),
})
```

---
**Runbook Created:** 2026-01-31
**Status:** Validated
