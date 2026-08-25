import { spawn, spawnSync } from "node:child_process";

const next = new URL("../../node_modules/next/dist/bin/next", import.meta.url).pathname;
const build = spawnSync(process.execPath, [next, "build"], { cwd: new URL("../../", import.meta.url), env: process.env, stdio: "inherit" });
if (build.status !== 0) process.exit(build.status ?? 1);

const server = spawn(process.execPath, [next, "start", "--hostname", "127.0.0.1", "--port", process.env.REAL_LOCAL_NEXT_PORT ?? "3200"], {
  cwd: new URL("../../", import.meta.url),
  env: process.env,
  stdio: "inherit",
});

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => server.kill(signal));
}
server.once("exit", (code, signal) => process.exit(code ?? (signal ? 1 : 0)));
