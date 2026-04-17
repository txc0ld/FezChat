import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.toml" },
        miniflare: {
          bindings: {
            JWT_SECRET: "test-jwt-secret",
            DATABASE_URL: "postgresql://test",
            INTERNAL_API_KEY: "test-internal-api-key",
            CORS_ORIGIN: "*",
          },
        },
      },
    },
  },
});
