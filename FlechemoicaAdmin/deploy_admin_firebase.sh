#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="/Users/nathanpiaget/Library/Mobile Documents/com~apple~CloudDocs/flechemoica"
ADMIN_DIR="$REPO_DIR/FlechemoicaAdmin"

PROJECT_ID="flechemoica"
HOSTING_TARGET="admin"

LOG_FILE="${TMPDIR:-/tmp}/flechemoica-deploy.log"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
    log "ERREUR: $*"
    log "Voir le log complet: $LOG_FILE"
    exit 1
}

run() {
    log "+ $*"
    "$@"
}

deploy_firebase_admin() {
    log "Debut du deploiement Firebase admin"
    log "Projet local: $ADMIN_DIR"
    log "Projet Firebase: $PROJECT_ID"

    cd "$ADMIN_DIR" || fail "Impossible d'ouvrir le dossier du projet admin."

    [ -f "firebase.json" ] || fail "firebase.json introuvable dans $ADMIN_DIR."
    [ -f ".firebaserc" ] || fail ".firebaserc introuvable dans $ADMIN_DIR."
    [ -f "public/index.html" ] || fail "public/index.html introuvable."

    if command -v firebase >/dev/null 2>&1; then
        FIREBASE_CMD=(firebase)
    elif command -v npx >/dev/null 2>&1; then
        FIREBASE_CMD=(npx --yes firebase-tools)
    else
        fail "Firebase CLI introuvable. Installe-le avec : npm install -g firebase-tools"
    fi

    log "Verification de la session Firebase"
    run "${FIREBASE_CMD[@]}" projects:list --non-interactive >/dev/null

    log "Deploiement hosting:$HOSTING_TARGET"

    run "${FIREBASE_CMD[@]}" deploy \
        --project "$PROJECT_ID" \
        --only "hosting:$HOSTING_TARGET" \
        --non-interactive

    log "Deploiement Firebase admin termine avec succes"
}

deploy_github_pages() {
    log "Debut de la publication GitHub Pages"
    log "Depot local: $REPO_DIR"

    cd "$REPO_DIR" || fail "Impossible d'ouvrir le depot Git."

    [ -d ".git" ] || fail "Aucun depot Git trouve dans $REPO_DIR."
    [ -d "docs" ] || fail "Le dossier docs est introuvable."

    command -v git >/dev/null 2>&1 || fail "Git est introuvable."

    if [ -n "$(git status --porcelain --untracked-files=all -- docs)" ]; then
        log "Ajout des modifications du dossier docs"
        run git add -A -- docs

        if ! git diff --cached --quiet -- docs; then
            COMMIT_MESSAGE="Mise a jour du site $(date '+%Y-%m-%d %H:%M:%S')"

            log "Creation du commit GitHub Pages"
            run git commit -m "$COMMIT_MESSAGE" -- docs
        else
            log "Aucune modification a committer dans docs."
        fi
    else
        log "Aucune nouvelle modification dans le dossier docs."
    fi

    run git fetch origin main

    if [ -n "$(git log --oneline origin/main..main)" ]; then
        log "Envoi des commits locaux vers GitHub"
        run git push origin main
        log "Publication GitHub Pages terminee avec succes"
    else
        log "Aucun commit local en attente de publication."
    fi
}

{
    log "Debut du deploiement complet"

    deploy_firebase_admin
    deploy_github_pages

    log "Tous les deploiements sont termines avec succes"
} 2>&1 | tee "$LOG_FILE"
