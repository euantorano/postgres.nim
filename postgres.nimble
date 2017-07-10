# Package

version       = "0.1.0"
author        = "Euan T"
description   = "A PostgreSQL client library for Nim."
license       = "BSD3"

srcDir = "src"

# Dependencies

requires "nim >= 0.17.0"

task docs, "Build documentation":
  exec "nim doc --index:on -o:docs/postgres.html src/postgres.nim"

task test, "Run tests":
  exec "nim c -r tests/main.nim"
