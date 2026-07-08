#!/usr/bin/env bash
# Interactive Turnip variant builder for the ROCKNIX GPU Driver Manager.
#
# Walks you through: pick a Mesa base -> (optionally) cherry-pick GitLab Merge
# Requests -> (optionally) apply local .patch files -> name it -> build it in the
# ROCKNIX toolchain -> publish to your catalogue (aanze/rocknix-turnip). The
# device then sees it under "Refresh catalog".
#
# This is the KIMCHI/Mr.Turnip workflow done right for ROCKNIX (glibc, not
# Android/bionic): same Mesa source + the same cherry-pick culture, your build.
#
# Launched 1-click from Windows by turnip-builder.bat (runs this through WSL).
set -uo pipefail

REPO_DIR="${REPO_DIR:-/home/marc/src/rocknix}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MESA="${MESA_SRC:-$SCRIPT_DIR/.mesa-src}"          # persistent partial clone
MESA_GIT="https://gitlab.freedesktop.org/mesa/mesa.git"
CI="$REPO_DIR/projects/ROCKNIX/packages/tools/gpu-driver/ci/build-turnip-catalog.sh"
RELEASE_REPO="${RELEASE_REPO:-aanze/rocknix-turnip}"
TAG="${TAG:-catalog}"
OUTDIR="$SCRIPT_DIR/.turnip-build"
FORKS_FILE="${FORKS_FILE:-$SCRIPT_DIR/turnip-forks.txt}"
ANDROID_REPOS_FILE="${ANDROID_REPOS_FILE:-$SCRIPT_DIR/turnip-android-repos.txt}"

c_hd()  { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }
c_ok()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_warn(){ printf '\033[1;33m%s\033[0m\n' "$*"; }
c_err() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; }
ask()   { local p="$1" d="${2:-}" a; read -r -p "$p${d:+ [$d]}: " a; printf '%s' "${a:-$d}"; }

[ -f "$CI" ] || { c_err "CI script missing: $CI"; exit 1; }
command -v git >/dev/null || { c_err "git not found"; exit 1; }

# ---------------------------------------------------------------- mesa clone
ensure_mesa() {
  if [ ! -d "$MESA/.git" ]; then
    c_hd "First run: cloning Mesa (partial clone, ~1-2 min)"
    git clone --filter=blob:none "$MESA_GIT" "$MESA" || { c_err "clone failed"; exit 1; }
  fi
  c_hd "Updating Mesa source"
  git -C "$MESA" fetch --tags --prune origin || c_warn "fetch failed (offline?) - using what's cached"
}

# ---------------------------------------------------------------- base picker
pick_base() {
  c_hd "Choose the Mesa BASE" >&2
  local opts=("Latest stable release" "Pick a stable tag" "Latest mesa-git (main, bleeding edge)" "Specific commit / branch / tag")
  local PS3=$'\n''Base> '
  local choice
  select choice in "${opts[@]}"; do [ -n "$choice" ] && break; done
  case "$REPLY" in
    1) BASE_REF=$(git -C "$MESA" tag -l 'mesa-*' | sort -V | tail -1); BASE_KIND=stable; BASE_LABEL="${BASE_REF#mesa-}" ;;
    2) local latest_tag; latest_tag=$(git -C "$MESA" tag -l 'mesa-*' | sort -V | tail -1)
       git -C "$MESA" tag -l 'mesa-*' | sort -V | tail -15 >&2
       BASE_REF=$(ask "Tag (e.g. ${latest_tag:-mesa-26.1.4})"); BASE_KIND=stable; BASE_LABEL="${BASE_REF#mesa-}" ;;
    3) BASE_REF="origin/main"; BASE_KIND=git; BASE_LABEL="git-$(git -C "$MESA" rev-parse --short origin/main 2>/dev/null)" ;;
    4) BASE_REF=$(ask "commit/branch/tag"); BASE_KIND=git; BASE_LABEL="git-$(echo "$BASE_REF" | tr '/:' '--')" ;;
    *) c_err "invalid"; exit 2 ;;
  esac
  git -C "$MESA" rev-parse --verify -q "${BASE_REF}^{commit}" >/dev/null 2>&1 \
    || git -C "$MESA" rev-parse --verify -q "${BASE_REF}" >/dev/null 2>&1 \
    || { c_err "base '$BASE_REF' not found"
         if [ "$BASE_KIND" = stable ]; then
           local latest devel
           latest=$(git -C "$MESA" tag -l 'mesa-*' | sort -V | tail -1)
           devel=$(git -C "$MESA" show origin/main:VERSION 2>/dev/null || true)
           c_warn "That Mesa release does not exist upstream (yet)."
           c_warn "Newest stable tag: ${latest}.  Unreleased series (currently ${devel:-?})"
           c_warn "only exist on mesa main -> pick base 3 (latest mesa-git) to build it."
         fi
         exit 2; }
  c_ok "Base = $BASE_REF"
}

# ---------------------------------------------------------------- MR picker
MRS=(); PATCHES=(); EXTS=()
_load_forks() {  # -> FNAMES[] FURLS[]
  FNAMES=(); FURLS=(); local nm ur
  [ -f "$FORKS_FILE" ] || return 0
  while IFS='|' read -r nm ur; do
    nm="$(printf '%s' "$nm" | sed 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//')"
    ur="$(printf '%s' "$ur" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$nm" ] && [ -n "$ur" ] && { FNAMES+=("$nm"); FURLS+=("$ur"); }
  done < "$FORKS_FILE"
}

# Interactive: pick a fork, then SEARCH/pick one of its branches.
# Sets globals SEL_URL + SEL_REF (both empty if cancelled). Uses globals (not
# echo) so the menus print straight to the console without capture games.
# Browse + search the branches of a known git URL. Sets SEL_REF (empty=cancel).
pick_branch_of() {
  local url="$1"; SEL_REF=""
  local kw; kw=$(ask "  search branches by keyword (blank=all; e.g. gen8, a830, a game)")
  c_hd "Branches on ${url}${kw:+  (matching '$kw')}"
  local flt; if [ -n "$kw" ]; then flt=(grep -i -e "$kw"); else flt=(cat); fi
  local brs=() i
  mapfile -t brs < <(git ls-remote --heads "$url" 2>/dev/null | sed 's#.*refs/heads/##' | "${flt[@]}" | sort | head -40)
  if [ "${#brs[@]}" -eq 0 ]; then
    c_warn "no branches (URL unreachable, or no match)."
    return 0
  fi
  for i in "${!brs[@]}"; do printf "  %d) %s\n" "$((i + 1))" "${brs[$i]}"; done
  c_warn "  ROCKNIX uses DRM/MSM, not KGSL -> avoid 'kgsl'/'hacks' branches; prefer 'clean'/DRM ones."
  local b; b=$(ask "  pick branch number (or type a ref; blank=cancel)")
  [ -z "$b" ] && return 0
  case "$b" in (*[!0-9]*) SEL_REF="$b" ;; (*) SEL_REF="${brs[$((b - 1))]:-}" ;; esac
}

browse_fork_branch() {
  SEL_URL=""; SEL_REF=""
  _load_forks
  local i
  echo
  for i in "${!FNAMES[@]}"; do printf "  %d) %s\n" "$((i + 1))" "${FNAMES[$i]}"; done
  printf "  c) custom git URL\n  x) cancel\n"
  local sel url; sel=$(ask "Pick a fork (number / c / x)" "x")
  case "$sel" in
    x|"") return 0 ;;
    c) url=$(ask "fork git URL"); [ -z "$url" ] && return 0 ;;
    *[!0-9]*) c_warn "?"; return 0 ;;
    *) url="${FURLS[$((sel - 1))]:-}"; [ -z "$url" ] && { c_warn "out of range"; return 0; } ;;
  esac
  pick_branch_of "$url"
  [ -z "$SEL_REF" ] && return 0
  SEL_URL="$url"
}

pick_exts() {  # advanced: add EXTRA fork branches to cherry-pick on top of the base
  c_hd "Add fork branches to cherry-pick on top (optional)"
  while :; do
    browse_fork_branch
    [ -z "$SEL_URL" ] && break
    EXTS+=("${SEL_URL}|${SEL_REF}"); c_ok "  + ${SEL_REF} @ ${SEL_URL}"
    [ "$(ask 'Add another? (y/N)')" = "y" ] || break
  done
}
# Find a published driver by NAME across the Android release repos, and resolve
# the Mesa SOURCE it was "build from:" so we can build it for glibc. Sets
# SEL_URL + SEL_REF (the source git url + branch).
search_published() {
  SEL_URL=""; SEL_REF=""
  command -v gh >/dev/null || { c_err "gh CLI needed for the search"; return 0; }
  local repos=() r
  if [ -f "$ANDROID_REPOS_FILE" ]; then
    while read -r r; do r="${r%%#*}"; r="$(printf '%s' "$r" | xargs)"; [ -n "$r" ] && repos+=("$r"); done < "$ANDROID_REPOS_FILE"
  fi
  [ "${#repos[@]}" -gt 0 ] || { c_warn "no repos listed in $ANDROID_REPOS_FILE"; return 0; }
  local kw; kw=$(ask "Driver name / keyword (e.g. Gen8, a830, V30)")
  [ -z "$kw" ] && return 0
  c_hd "Searching published driver releases for '$kw' (+ their Mesa source)..."
  local cands=()
  mapfile -t cands < <(python3 - "$kw" "${repos[@]}" <<'PY'
import sys, json, re, subprocess
kw = sys.argv[1].lower(); repos = sys.argv[2:]
tree = re.compile(r'https?://github\.com/([\w.-]+)/([\w.-]+?)(?:\.git)?/tree/([^\s)\]]+)')
bare = re.compile(r'https?://github\.com/([\w.-]+)/([\w.-]+?)(?:\.git)?(?=[\s)\].,]|$)')
def fam(s):  # name tokens minus version/revision tokens (v30, r7, 26.2.0 ...)
    return set(t for t in re.findall(r'[a-z0-9.]+', s.lower())
               if not re.fullmatch(r'[vr]?\d+(\.\d+)*', t))
def srcof(body):
    b = body or ""
    m = tree.search(b)            # explicit .../tree/<branch>
    if m:
        return (f"https://github.com/{m.group(1)}/{m.group(2)}.git", m.group(3).rstrip(".,);"))
    m = bare.search(b)            # bare repo URL, branch unknown (resolve interactively)
    if m:
        return (f"https://github.com/{m.group(1)}/{m.group(2)}.git", "")
    return None
for repo in repos:
    try:
        out = subprocess.run(["gh", "api", f"repos/{repo}/releases", "--paginate"],
                             capture_output=True, text=True, timeout=40)
        rels = json.loads(out.stdout) if out.returncode == 0 else []
    except Exception:
        rels = []
    # all releases in this repo that DO carry a source (newest first), for fallback
    have_src = [(rel.get("name") or rel.get("tag_name") or "", srcof(rel.get("body")))
                for rel in rels if srcof(rel.get("body"))]
    for rel in rels:
        name = rel.get("name") or ""; tag = rel.get("tag_name") or ""
        if kw not in (name + " " + tag).lower():
            continue
        s = srcof(rel.get("body"))
        if s:
            print(f"{s[0]}|{s[1]}|{repo}: {name or tag}  ->  {s[1]}")
            continue
        # no own source: pick the sibling release with the closest NAME
        f = fam(name or tag); best = None; bestov = 0
        for sn, ss in have_src:
            ov = len(f & fam(sn))
            if ov > bestov: best, bestov = ss, ov
        if best:
            print(f"{best[0]}|{best[1]}|{repo}: {name or tag}  (source via sibling -> {best[1]})")
        else:
            print(f"|{tag}|{repo}: {name or tag}  (no source found)")
PY
)
  [ "${#cands[@]}" -gt 0 ] || { c_warn "no match (or no source provenance). Try mode 1 and browse a source fork's branches."; return 0; }
  local i
  for i in "${!cands[@]}"; do
    local lbl="${cands[$i]}"; lbl="${lbl#*|}"; lbl="${lbl#*|}"
    printf "  %d) %s\n" "$((i + 1))" "$lbl"
  done
  local pick; pick=$(ask "pick a result number (blank=cancel)")
  [ -z "$pick" ] && return 0
  case "$pick" in (*[!0-9]*) c_warn "?"; return 0 ;; esac
  local sel="${cands[$((pick - 1))]:-}"; [ -z "$sel" ] && return 0
  SEL_URL="${sel%%|*}"; local rest="${sel#*|}"; SEL_REF="${rest%%|*}"
  if [ -z "$SEL_URL" ]; then
    c_warn "that release names no source repo — open it on GitHub, then use mode 1."
    SEL_REF=""; return 0
  fi
  # build-from gave a repo but no branch -> let the user pick a branch of THAT repo
  if [ -z "$SEL_REF" ]; then
    c_hd "Source is ${SEL_URL} (no branch stated) — pick its branch:"
    pick_branch_of "$SEL_URL"
    [ -z "$SEL_REF" ] && { c_warn "no branch chosen"; SEL_URL=""; return 0; }
  fi
  c_ok "source resolved: ${SEL_REF} @ ${SEL_URL}"
}

pick_mrs() {
  c_hd "Cherry-pick GitLab Merge Requests (optional)"
  echo "Enter a Mesa MR number to layer on top (e.g. 12345). Find them at"
  echo "https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests . Blank to finish."
  while :; do
    local n; n=$(ask "MR number (blank=done)")
    [ -z "$n" ] && break
    case "$n" in (*[!0-9]*) c_warn "digits only"; continue;; esac
    MRS+=("$n"); c_ok "  + MR !$n"
  done
}
pick_patches() {
  c_hd "Apply local .patch files (optional)"
  echo "Full path to a .patch/.diff to apply (e.g. /home/marc/mypatch.patch). Blank to finish."
  while :; do
    local p; p=$(ask "patch path (blank=done)")
    [ -z "$p" ] && break
    [ -f "$p" ] || { c_warn "no such file: $p"; continue; }
    PATCHES+=("$p"); c_ok "  + $(basename "$p")"
  done
}

# ---------------------------------------------------------------- prepare tree
prepare_tree() {  # cherry-pick MRs + apply patches onto BASE; echo tarball path
  git -C "$MESA" cherry-pick --abort >/dev/null 2>&1 || true
  git -C "$MESA" reset --hard >/dev/null 2>&1
  git -C "$MESA" clean -fdq >/dev/null 2>&1
  git -C "$MESA" checkout --detach "$BASE_REF" >/dev/null 2>&1 || { c_err "checkout base failed"; exit 1; }
  local id
  for id in "${MRS[@]}"; do
    c_hd "Cherry-picking MR !$id"
    git -C "$MESA" fetch -q origin "refs/merge-requests/$id/head:mr/$id" 2>/dev/null \
      || { c_err "could not fetch MR !$id (does it exist?)"; exit 1; }
    local mb; mb=$(git -C "$MESA" merge-base HEAD "mr/$id")
    if ! git -C "$MESA" cherry-pick --allow-empty "$mb..mr/$id" >/dev/null 2>&1; then
      git -C "$MESA" cherry-pick --abort >/dev/null 2>&1 || true
      c_err "MR !$id does NOT apply cleanly on this base (conflict). Pick a closer base (e.g. latest mesa-git) or drop this MR."
      exit 1
    fi
    c_ok "  applied MR !$id"
  done
  local i=0 e url ref
  for e in "${EXTS[@]}"; do
    i=$((i + 1)); url="${e%%|*}"; ref="${e#*|}"
    c_hd "Cherry-picking ${ref} from ${url}"
    git -C "$MESA" fetch -q "$url" "${ref}:refs/tmp/ext-$i" 2>/dev/null \
      || { c_err "could not fetch '${ref}' from ${url}"; exit 1; }
    local mbe; mbe=$(git -C "$MESA" merge-base HEAD "refs/tmp/ext-$i")
    if ! git -C "$MESA" cherry-pick --allow-empty "$mbe..refs/tmp/ext-$i" >/dev/null 2>&1; then
      git -C "$MESA" cherry-pick --abort >/dev/null 2>&1 || true
      c_err "branch '${ref}' from ${url} does NOT apply cleanly on this base. Try base = latest mesa-git, or a closer ref."
      exit 1
    fi
    c_ok "  applied ${ref}"
  done
  local p
  for p in "${PATCHES[@]}"; do
    c_hd "Applying patch $(basename "$p")"
    if ! git -C "$MESA" apply --index "$p" 2>/dev/null; then
      c_err "patch $(basename "$p") does not apply cleanly on this base."
      exit 1
    fi
    git -C "$MESA" commit -q -m "local patch: $(basename "$p")" || true
    c_ok "  applied $(basename "$p")"
  done
  mkdir -p "$OUTDIR"
  local tarball="$OUTDIR/mesa-${LABEL}.tar.gz"
  git -C "$MESA" archive --format=tar.gz --prefix="mesa-${LABEL}/" -o "$tarball" HEAD \
    || { c_err "git archive failed"; exit 1; }
  echo "$tarball"
}

# ============================================================ main flow
ensure_mesa

# Menu loops until we have a build target, so a dead-end search / cancel just
# returns here instead of quitting. 'q' at the menu exits.
while true; do
  MRS=(); EXTS=(); PATCHES=(); SEL_URL=""; SEL_REF=""; BASE_REF=""
  c_hd "What do you want to build?  (Ctrl-C or pick then cancel to abort)"
  modeopts=(
    "A contributor's branch, as-is   (pick a fork & search its branches)"
    "Find a driver by NAME across published repos   (e.g. 'Gen8 V30' — don't know the author)"
    "Official Mesa release (a stable tag)"
    "Latest mesa-git (main, bleeding edge)"
    "Advanced: a base + cherry-pick MRs / fork branches / patches"
    "Quit"
  )
  PS3=$'\n''Build> '
  select _m in "${modeopts[@]}"; do [ -n "$_m" ] && break; done
  case "$REPLY" in
    1) browse_fork_branch ;;                     # pick fork + branch (sets SEL_*)
    2) search_published ;;                       # find by name -> resolves SEL_* source
    3)
      git -C "$MESA" tag -l 'mesa-*' | sort -V | tail -15
      BASE_REF=$(ask "Stable tag (e.g. mesa-26.2.0; blank=back)"); [ -z "$BASE_REF" ] && continue
      BASE_KIND=stable; BASE_LABEL="${BASE_REF#mesa-}"
      git -C "$MESA" rev-parse --verify -q "${BASE_REF}^{commit}" >/dev/null 2>&1 \
        || { c_warn "tag '${BASE_REF}' not found — back to menu"; continue; }
      ;;
    4)
      BASE_REF="origin/main"; BASE_KIND=git
      BASE_LABEL="git-$(git -C "$MESA" rev-parse --short origin/main 2>/dev/null)"
      ;;
    5)
      pick_base; pick_mrs; pick_exts; pick_patches ;;
    6|q|Q) c_warn "bye"; exit 0 ;;
    *) c_warn "invalid choice"; continue ;;
  esac

  # Modes 1 & 2 resolve a fork URL + branch (SEL_*) -> fetch it as the build base.
  if [ "$REPLY" = 1 ] || [ "$REPLY" = 2 ]; then
    if [ -z "${SEL_URL:-}" ]; then c_warn "nothing selected — back to menu"; continue; fi
    c_hd "Fetching ${SEL_REF} from ${SEL_URL}"
    if ! git -C "$MESA" fetch -q "$SEL_URL" "${SEL_REF}:refs/tmp/forkbuild" 2>/dev/null; then
      c_warn "could not fetch '${SEL_REF}' from ${SEL_URL} — back to menu"; continue
    fi
    BASE_REF="refs/tmp/forkbuild"; BASE_KIND=git
    fb_sha="$(git -C "$MESA" rev-parse --short refs/tmp/forkbuild 2>/dev/null)"
    BASE_LABEL="$(printf '%s' "$SEL_REF" | tr '/:' '--')${fb_sha:+-$fb_sha}"
    c_ok "Will build '${SEL_REF}' @ ${fb_sha} as-is (glibc) — id pins this exact commit"
  fi

  [ -n "${BASE_REF:-}" ] && break
  c_warn "nothing to build — back to menu"
done

# default label
DEF_LABEL="$BASE_LABEL"
[ ${#MRS[@]} -gt 0 ] && DEF_LABEL="${DEF_LABEL}-mr$(IFS=-; echo "${MRS[*]}")"
[ ${#EXTS[@]} -gt 0 ] && DEF_LABEL="${DEF_LABEL}-fork"
[ ${#PATCHES[@]} -gt 0 ] && DEF_LABEL="${DEF_LABEL}-patched"
DEF_LABEL=$(echo "$DEF_LABEL" | tr -c 'A-Za-z0-9.-' '-' | sed 's/--*/-/g;s/^-//;s/-$//')
LABEL=$(ask "Driver name (id in your catalogue)" "$DEF_LABEL")
LABEL=$(echo "$LABEL" | tr -c 'A-Za-z0-9.-' '-' | sed 's/--*/-/g;s/^-//;s/-$//')
LABEL="${LABEL#turnip-}"   # the id becomes turnip-<LABEL>; avoid turnip-turnip-...

c_hd "Summary"
echo "  base    : $BASE_REF"
echo "  MRs     : ${MRS[*]:-(none)}"
echo "  forks   : ${EXTS[*]:-(none)}"
echo "  patches : ${PATCHES[*]:-(none)}"
echo "  id      : turnip-$LABEL"
echo "  publish : $RELEASE_REPO  (tag $TAG)"
[ "$(ask 'Build this? (y/N)')" = "y" ] || { c_warn "cancelled"; exit 0; }

# --- provenance log ------------------------------------------------------
# The catalogue id is freely renamed at the prompt above, so without this log
# the source reference (fork url/branch/commit) behind a published driver is
# unrecoverable — you can't rebuild "the driver you liked" later. Appends one
# block per successful publish to catalog-provenance.txt; the source tarball
# in .turnip-build/ is the exact tree (its embedded commit id = assembled HEAD,
# readable with: zcat <tarball> | git get-tar-commit-id).
PROV="$SCRIPT_DIR/catalog-provenance.txt"
log_provenance() {
  local id="$1" spec="$2"
  {
    echo "[$(date '+%F %H:%M')] id=$id"
    echo "  spec    : $spec"
    if [ -n "${TARBALL:-}" ] && [ -f "${TARBALL:-}" ]; then
      echo "  tarball : $TARBALL"
      echo "  commit  : $(zcat "$TARBALL" | git get-tar-commit-id 2>/dev/null || echo '?')  (assembled HEAD)"
    fi
    echo "  base    : $BASE_REF @ $(git -C "$MESA" rev-parse --short "${BASE_REF}" 2>/dev/null || echo '?')${SEL_URL:+  <- $SEL_REF from $SEL_URL}"
    [ ${#MRS[@]} -gt 0 ]     && echo "  MRs     : ${MRS[*]}"
    [ ${#EXTS[@]} -gt 0 ]    && echo "  forks   : ${EXTS[*]}"
    [ ${#PATCHES[@]} -gt 0 ] && echo "  patches : ${PATCHES[*]}"
    echo
  } >> "$PROV"
  c_ok "provenance logged -> $PROV"
}

cd "$REPO_DIR"
export PROJECT=ROCKNIX DEVICE=SM8750 ARCH=aarch64
# Stable tag with no patches -> fast path via the upstream release archive.
# Everything else (git base, or any MR/patch) -> build from the local clone
# (git archive), which is reliable + pinned. The GitLab archive endpoint chokes
# on remote-tracking refs like "origin/main", so we never feed it a git ref.
if [ "$BASE_KIND" = stable ] && [ ${#MRS[@]} -eq 0 ] && [ ${#EXTS[@]} -eq 0 ] && [ ${#PATCHES[@]} -eq 0 ]; then
  c_hd "Building stable:${BASE_REF#mesa-} (fast path)"
  "$CI" --repo "$RELEASE_REPO" --tag "$TAG" "stable:${BASE_REF#mesa-}"
  log_provenance "turnip-${BASE_REF#mesa-}-stable" "stable:${BASE_REF#mesa-}"
else
  TARBALL=$(prepare_tree) || exit 1
  c_ok "Prepared source: $TARBALL"
  c_hd "Building turnip-$LABEL in the ROCKNIX toolchain (~2-5 min)"
  "$CI" --repo "$RELEASE_REPO" --tag "$TAG" "src:${LABEL}:${TARBALL}"
  log_provenance "turnip-$LABEL" "src:${LABEL}:${TARBALL}"
fi
