import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        isolatedStorage: false,
        wrangler: {
          configPath: "./wrangler.toml",
        },
        miniflare: {
          // The wrangler.toml declares a service binding to `blip-auth`. In
          // tests we don't have the auth Worker available; PushDispatcher
          // tests pass an Env stub without AUTH so the code path falls back
          // to globalThis.fetch (which the tests already stub). This mock
          // only exists to satisfy miniflare's binding resolution.
          serviceBindings: {
            AUTH: () =>
              new Response("auth binding is mocked in tests", { status: 599 }),
          },
        },
      },
    },
  },
});
