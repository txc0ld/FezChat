import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.toml" },
        miniflare: {
          r2Buckets: ["AVATARS"],
          bindings: {
            JWT_SECRET: "test-jwt-secret",
            DATABASE_URL: "postgresql://test",
            INTERNAL_API_KEY: "test-internal-api-key",
            CORS_ORIGIN: "*",
            MAX_AVATAR_BYTES: "2097152",
            // 32-byte seed (0x01..0x20) || 32-byte derived public key — see test/manifest-signature.test.ts.
            MANIFEST_SIGNING_KEY:
              "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyB5tVYuj+ZU+UB4sRLoqYunkB+FOuaVvtfg45ELrQSWZA==",
          },
        },
      },
    },
  },
});
