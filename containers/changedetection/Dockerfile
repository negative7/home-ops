# changedetection.io + the CloakBrowser stealth fetcher plugin.
# The plugin launches Chromium inside this container (it cannot use the sockpuppetbrowser
# sidecar), so the image needs Chromium's system libraries. The CloakBrowser binary itself is
# closed source and is downloaded at runtime into CLOAKBROWSER_CACHE_DIR, not baked in here.
FROM ghcr.io/dgtlmoon/changedetection.io:0.70.4@sha256:b6aae2572a0bf1a671b1b202365ddcfe16a31fa8a60be89df606705731b55f8b

# renovate: datasource=pypi depName=changedetection.io-cloak-browser
ARG CLOAK_PLUGIN_VERSION=0.1.1
# renovate: datasource=pypi depName=cloakbrowser
ARG CLOAKBROWSER_VERSION=0.7.3

# Chromium runtime libraries, matched to the image's own Playwright version
RUN playwright install-deps chromium \
    && rm -rf /var/lib/apt/lists/*

# --no-deps on the plugin: it requires the changedetection.io PyPI package, which the image
# runs from source in /app instead, so a normal install would pull a second copy.
# cloakbrowser's own deps (playwright, httpx, cryptography) already ship in the base image.
RUN pip install --no-cache-dir --no-deps "changedetection.io-cloak-browser==${CLOAK_PLUGIN_VERSION}" \
    && pip install --no-cache-dir "cloakbrowser==${CLOAKBROWSER_VERSION}" \
    && python3 -c "import changedetection_cloak_browser, cloakbrowser"
