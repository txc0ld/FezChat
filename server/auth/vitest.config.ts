import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.toml" },
        miniflare: {
          kvNamespaces: ["CODES"],
          bindings: {
            RESEND_API_KEY: "re_test_fake_key",
            FROM_EMAIL: "verify@blip.app",
            CODE_TTL_SECONDS: "600",
            MAX_SENDS_PER_HOUR: "3",
            JWT_SECRET: "test-jwt-secret",
            JWT_EXPIRY_SECONDS: "3600",
            JWT_REFRESH_GRACE_SECONDS: "300",
          },
          // The wrangler.toml declares a service binding to `blip-relay`. In
          // tests we don't have the relay Worker available, so the auth code
          // falls back to globalThis.fetch (which the test suite stubs). This
          // mock satisfies miniflare's binding resolution without touching
          // production behaviour.
          serviceBindings: {
            RELAY: () =>
              new Response("relay binding is mocked in tests", { status: 599 }),
          },
        },
      },
    },
  },
});
