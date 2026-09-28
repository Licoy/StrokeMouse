/** App marketing version — keep in sync with project.yml MARKETING_VERSION */
export const APP_VERSION = '0.0.30'

/**
 * Built-in preset actions shown on the homepage strip.
 * 7 default mouse strokes (`DefaultGestures.make`) +
 * 12 trackpad common presets (`TrackpadGesturePresetCatalog.balanced`).
 */
export const PRESET_ACTION_COUNT = '19+'

export const GITHUB_REPO = 'https://github.com/Licoy/StrokeMouse'
export const GITHUB_RELEASES = `${GITHUB_REPO}/releases`
export const GITHUB_RELEASE_TAG = `${GITHUB_RELEASES}/tag/v${APP_VERSION}`

/** Artifact base for a given release tag */
export const RELEASE_DOWNLOAD_BASE = `${GITHUB_REPO}/releases/download/v${APP_VERSION}`

export function releaseAssetUrl(filename: string): string {
  return `${RELEASE_DOWNLOAD_BASE}/${filename}`
}

export const MAC_ASSETS = {
  arm64: {
    file: 'StrokeMouse-macos-arm64.dmg',
    arch: 'arm64' as const,
  },
  x64: {
    file: 'StrokeMouse-macos-x86_64.dmg',
    arch: 'x86_64' as const,
  },
}
