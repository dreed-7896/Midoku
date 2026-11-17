// App lock backed by a device passkey: unlocking asks for Face ID, Touch ID or the device's fingerprint.
// The check happens on this device only, so it is a privacy screen rather than encryption.

const random = (n: number) => crypto.getRandomValues(new Uint8Array(n))

const toB64 = (buf: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(buf)))
const fromB64 = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0))

export async function lockSupported(): Promise<boolean> {
  try {
    return !!window.PublicKeyCredential && (await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable())
  } catch {
    return false
  }
}

/** Creates the passkey; returns its credential id. */
export async function createLock(): Promise<string> {
  const cred = (await navigator.credentials.create({
    publicKey: {
      challenge: random(32),
      rp: { name: 'Midoku', id: location.hostname },
      user: { id: random(16), name: 'Midoku app lock', displayName: 'Midoku app lock' },
      pubKeyCredParams: [{ type: 'public-key', alg: -7 }, { type: 'public-key', alg: -257 }],
      authenticatorSelection: { authenticatorAttachment: 'platform', userVerification: 'required', residentKey: 'preferred' },
      timeout: 60_000,
      attestation: 'none',
    },
  })) as PublicKeyCredential | null
  if (!cred) throw new Error('No passkey was created')
  return toB64(cred.rawId)
}

/** Resolves when the person passes Face ID / Touch ID for the stored passkey. */
export async function unlock(credentialId: string): Promise<void> {
  const result = await navigator.credentials.get({
    publicKey: {
      challenge: random(32),
      rpId: location.hostname,
      allowCredentials: [{ type: 'public-key', id: fromB64(credentialId), transports: ['internal', 'hybrid'] }],
      userVerification: 'required',
      timeout: 60_000,
    },
  })
  if (!result) throw new Error('Unlock was cancelled')
}
