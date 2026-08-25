name = "poipoiiii/agent-runtime"

version = "0.1.0"

description = "Lightweight AI Agent Runtime based on MoonBit"

preferred_target = "native"

readme = "README.md"

repository = "https://github.com/poipoiiii/MoonBit_ws"

license = "MIT"

keywords = [ "agent", "ai", "llm", "runtime", "deepseek" ]

import {
  "moonbitlang/async@0.20.2",
}

options(
  exclude: [ "scratch_test" ],
)
