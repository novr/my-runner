-include .env
export

.PHONY: setup spawn spawn-repo pool pool-repo clean prune-runners plist-install plist-uninstall

## First-time host setup (install tart, sshpass, jq; pull base image)
setup:
	bash host/setup.sh

## Spawn a single runner targeting GITHUB_ORG (from .env)
spawn:
	bash scripts/spawn.sh

## Spawn a single runner targeting a specific repo
##   make spawn-repo REPO=owner/repo
spawn-repo:
	bash scripts/spawn.sh --repo "$(REPO)"

## Start the org-level pool manager in the foreground
pool:
	bash scripts/pool.sh

## Start a repo-level pool manager in the foreground
##   make pool-repo REPO=owner/repo
pool-repo:
	bash scripts/pool.sh --repo "$(REPO)"

## Delete all orphaned runner VMs (prefix: <target>-runner-)
clean:
	@tart list 2>/dev/null | awk '$$2 ~ /-runner-/ { print $$2 }' \
	  | xargs -I{} sh -c 'echo "Deleting {}"; tart delete {}' || true

## Remove offline GitHub runner registrations left by aborted JIT spawns
##   make prune-runners
##   make prune-runners REPO=novr/Rin
prune-runners:
	bash scripts/prune-runners.sh $(if $(REPO),--repo "$(REPO)",)

## Install pool manager as a launchd service (edit REPO_PATH in the plist first)
plist-install:
	cp host/com.myrunner.pool.plist ~/Library/LaunchAgents/
	launchctl load ~/Library/LaunchAgents/com.myrunner.pool.plist

## Uninstall launchd service
plist-uninstall:
	launchctl unload ~/Library/LaunchAgents/com.myrunner.pool.plist
	rm -f ~/Library/LaunchAgents/com.myrunner.pool.plist
