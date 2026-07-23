-include .env
export

.PHONY: setup spawn pool clean plist-install plist-uninstall

## First-time host setup (install tart, sshpass, jq; pull base image)
setup:
	bash host/setup.sh

## Spawn a single ephemeral runner (blocks until job completes)
spawn:
	bash scripts/spawn.sh

## Start the pool manager in the foreground (keeps POOL_SIZE runners alive)
pool:
	bash scripts/pool.sh

## Delete all orphaned runner VMs (names starting with "runner-")
clean:
	@tart list 2>/dev/null | grep '^runner-' | awk '{print $$1}' \
	  | xargs -I{} sh -c 'echo "Deleting {}"; tart delete {}' || true

## Install pool manager as a launchd service (edit REPO_PATH in the plist first)
plist-install:
	cp host/com.myrunner.pool.plist ~/Library/LaunchAgents/
	launchctl load ~/Library/LaunchAgents/com.myrunner.pool.plist

## Uninstall launchd service
plist-uninstall:
	launchctl unload ~/Library/LaunchAgents/com.myrunner.pool.plist
	rm -f ~/Library/LaunchAgents/com.myrunner.pool.plist
