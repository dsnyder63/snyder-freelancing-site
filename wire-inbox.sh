#!/bin/bash
# Wires both mobile quote & sign pages to auto-submit signed quotes to the
# proposal inbox on "Sign & finish". The text-to-Daniel SMS button stays as fallback.
#
# Usage: wire-inbox.sh <inbox-base-url>
#   e.g. wire-inbox.sh https://snyder-freelancing-hq.onrender.com
#
# Does: injects INBOX_API + a fire-and-forget fetch() into finish() in both
#   pages (cake-factory-sign -> sourcePage "cake-factory",
#   massage-sign -> sourcePage "massage-referral"), commits, and pushes
#   dsnyder63/snyder-freelancing (Render auto-deploys both static sites).
#
# The fetch never blocks or breaks the SMS flow: it is wrapped in try/catch
# and failures are swallowed silently (quiet .catch).
set -euo pipefail

BASE="${1:?usage: wire-inbox.sh <inbox-base-url>}"
BASE="${BASE%/}"
API="$BASE/api/submit"
ROOT="$HOME/workspace/snyder-freelancing"
export PYTHONPATH=/opt/muse/skills/custom-connector-setup/bin
GH="$HOME/workspace/custom-connectors/custom.legacy-github/bin/gh.py"

wire_page() { # $1=page dir, $2=sourcePage label
  local page="$1" label="$2" f="$ROOT/$page/index.html"
  echo "--- wiring $page (sourcePage=$label)"
  python3 - "$f" "$API" "$label" <<'PYEOF'
import sys
path, api, label = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path).read()

# 1) INBOX_API const, inserted right before finish()
anchor_cfg = "      function finish() {"
cfg_line = '      var INBOX_API = "%s";\n' % api
assert src.count(anchor_cfg) == 1, "expected exactly 1 finish() in %s, found %d" % (path, src.count(anchor_cfg))
assert "INBOX_API" not in src, "page already wired: %s" % path
src = src.replace(anchor_cfg, cfg_line + anchor_cfg, 1)

# 2) auto-submit snippet, right after the finalText build
anchor_txt = "        finalText = buildSummaryText(pkg, plan, m, a, signer, sigDate);"
assert src.count(anchor_txt) == 1, "expected exactly 1 summary line in %s, found %d" % (path, src.count(anchor_txt))
snippet = """
        /* ---- auto-submit signed quote to the proposal inbox (SMS fallback still works) ---- */
        try {
          if (INBOX_API) {
            var __addons = (typeof selectedAddons === "function") ? selectedAddons().map(function (ad) { return ad.name; }) : [];
            fetch(INBOX_API, {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({
                sourcePage: "%s",
                signerName: signer,
                package: pkg.name,
                paymentPlan: plan.months === 0 ? "Pay in full" : (plan.label + (plan.apr ? " at " + aprPct(plan.apr) + " APR" : " at 0%% APR")),
                addons: __addons,
                questionnaire: a,
                summaryText: finalText,
                signatureDataUrl: canvas.toDataURL("image/png")
              })
            }).catch(function () { /* quiet: text-to-Daniel button stays as the fallback */ });
          }
        } catch (e) {}
""" % label
src = src.replace(anchor_txt, anchor_txt + snippet, 1)
open(path, "w").write(src)
print("wired OK:", path)
PYEOF
}

wire_page cake-factory-sign cake-factory
wire_page massage-sign massage-referral

cd "$ROOT"
git add cake-factory-sign/index.html massage-sign/index.html
git -c user.name="Broski" -c user.email="broski@local" commit -m "Auto-submit signed quotes to proposal inbox on Sign & finish ($BASE)"
python3 "$GH" push . dsnyder63/snyder-freelancing
echo "pushed. Render will redeploy both static sites automatically."
