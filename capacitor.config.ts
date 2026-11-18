import type { CapacitorConfig } from '@capacitor/cli'

/**
 * iOS app shell. It loads the deployed site, so every Vercel deploy reaches the app the same way it reaches the
 * browser (the service worker's "Restart to update"). The site is an app-bound domain, which lets WKWebView run
 * the service worker and keep Cache Storage, so the app opens offline after the first launch.
 * Native plugins (on-device extensions) are bundled in the shell and only change with a new IPA.
 */
const config: CapacitorConfig = {
  appId: 'com.raahat.MidokuWeb',
  appName: 'Midoku',
  webDir: 'dist',
  backgroundColor: '#09090b',
  server: {
    url: 'https://midoku-web-six.vercel.app',
    allowNavigation: ['midoku-web-six.vercel.app'],
  },
  ios: {
    contentInset: 'never',
    backgroundColor: '#09090b',
    limitsNavigationsToAppBoundDomains: true,
    scrollEnabled: true,
  },
}

export default config
