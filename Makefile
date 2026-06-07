# Image build helpers. Day-to-day lifecycle goes through `dwe` directly.
#
# PHP base image tag (also the image registry tag), e.g. 8.5
PHP_VERSION ?= 8.5

.PHONY: build-php-base-image pull-base-image

# Build & push the multi-arch base PHP image for the Magento service
# to ghcr.io/semsemyonoff/dwe-magento-php. Requires `docker login ghcr.io`.
build-php-base-image:
	@bash images/services/magento/base/build.sh $(PHP_VERSION)

# Pull the published base image (no build) — useful on a fresh machine.
pull-base-image:
	@docker pull ghcr.io/semsemyonoff/dwe-magento-php:$(PHP_VERSION)
