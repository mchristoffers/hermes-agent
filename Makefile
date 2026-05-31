.PHONY: build tag

# Build the deploy image via GitHub Actions and push it to GHCR.
#
# These targets just drive the "Build deploy image" workflow
# (.github/workflows/build-image.yml) with the gh CLI — the actual build runs
# on GitHub, not here. `-R` is REQUIRED: this fork carries an `upstream` remote
# (NousResearch), so a bare `gh` resolves to upstream and 404s.

REPO := mchristoffers/hermes-agent
REF  ?= main

# Trigger a build of REF (default: main). Prints how to get the tag.
build:
	gh workflow run build-image.yml -R $(REPO) -f ref=$(REF)
	@echo "Build triggered for ref=$(REF). When it finishes: make tag"

# Print the short-SHA image tag of the most recent build run (use it as the
# tag to deploy in the hermes repo: `make deploy TAG=<sha>`).
tag:
	@gh run view -R $(REPO) \
	  $$(gh run list -R $(REPO) --workflow=build-image.yml -L1 --json databaseId -q '.[].databaseId') \
	  --json headSha -q '.headSha[0:12]'
