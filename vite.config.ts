import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// @vuu-ui/* packages are consumed here as ordinary published npm packages
// (built esm/cjs, no raw .tsx/.css source to resolve) - no workspace-symlink
// or path-mapping plugins needed, unlike the monorepo this app was split out
// of.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 4173,
  },
});
