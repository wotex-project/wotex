import { registerHooks } from "node:module"
import { resolve } from "./alias_loader.ts"

registerHooks({ resolve })
