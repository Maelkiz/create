# Sourced by pre-commit and pre-push: the paths a change may touch and still
# skip every check, since nothing here can reach a build or a test. It is an
# allowlist on purpose — pixi.toml, scripts/, fixtures and assets look inert
# and are not, so any path not named here means the full run.
is_inert() {
    case "$1" in
        *.md | LICENSE | .gitignore | .git-blame-ignore-revs \
            | .agents/* | .claude/* | .vscode/* | skills-lock.json) return 0 ;;
    esac
    return 1
}
