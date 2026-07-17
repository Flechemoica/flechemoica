#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/Users/nathanpiaget/Library/Mobile Documents/com~apple~CloudDocs/flechemoica/FlechemoicaAdmin"
PROJECT_ID="flechemoica"
HOSTING_TARGET="admin"
LOG_FILE="${TMPDIR:-/tmp}/flechemoica-admin-firebase-deploy.log"

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

{
    log "Debut du deploiement Firebase admin"
    log "Projet local: $PROJECT_DIR"
    log "Projet Firebase: $PROJECT_ID"

    cd "$PROJECT_DIR" || fail "Impossible d'ouvrir le dossier du projet."

    [ -f "firebase.json" ] || fail "firebase.json introuvable dans $PROJECT_DIR."
    [ -f ".firebaserc" ] || fail ".firebaserc introuvable dans $PROJECT_DIR."
    [ -f "public/index.html" ] || fail "public/index.html introuvable."
    [ -f "functions/package.json" ] || fail "functions/package.json introuvable."

    if command -v firebase >/dev/null 2>&1; then
        FIREBASE_CMD=(firebase)
    elif command -v npx >/dev/null 2>&1; then
        FIREBASE_CMD=(npx --yes firebase-tools)
    else
        fail "Firebase CLI introuvable. Installe-le avec: npm install -g firebase-tools"
    fi

    if command -v npm >/dev/null 2>&1; then
        if [ ! -d "functions/node_modules" ]; then
            log "Installation des dependances Cloud Functions"
            run npm --prefix functions install
        else
            log "Dependances Cloud Functions deja presentes"
        fi
    else
        fail "npm introuvable. Installe Node.js avant de deployer les fonctions."
    fi

    log "Verification de la session Firebase"
    run "${FIREBASE_CMD[@]}" projects:list --non-interactive >/dev/null

    log "Deploiement functions + hosting:$HOSTING_TARGET"
    run "${FIREBASE_CMD[@]}" deploy \
        --project "$PROJECT_ID" \
        --only "functions,hosting:$HOSTING_TARGET" \
        --non-interactive

    log "Deploiement termine avec succes"
} 2>&1 | tee "$LOG_FILE"
