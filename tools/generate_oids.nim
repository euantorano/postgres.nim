## This tool will generate a Nim enum describing each Postgres type by OID.

import parseopt2, os, osproc, strutils, strscans

const
  OutFileTypeSection = r"""## Mapping of Postgres OIDs to types.
##
## This file is generated automatically by the `tools/generate_oids` program.

type
  Oid* {.pure.} = enum"""

  Command = "psql -c 'SELECT typname, oid FROM pg_type WHERE oid < 10000 ORDER BY oid;'"


proc main() =
  var outFile = "./src/postgres/private/oids.nim"

  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "ooutput", "o":
        outFile = val
      else: discard
    else: discard

  let outputFile = open(outFile, fmWrite)
  defer: close(outputFile)

  outputFile.writeLine(OutFileTypeSection)

  let output = execProcess(Command)

  var
    lineNumber: int = 1
    numTypes: int = 0
    name: string
    oid: int
    enumLine: string

  for line in output.splitLines():
    if lineNumber > 2 and len(line) > 0:
      # Line is in the form: ` bool                                  |    16` - `bool` is the type name, `16` is the OID
      if scanf(line, "$s$w$s|$s$i$s", name, oid):
        if name[0] == '_':
          enumLine = "    T" & name & " = Oid(" & $oid & ")"
        else:
          enumLine = "    " & capitalizeAscii(name) & " = int32(" & $oid & ")"

        outputFile.writeLine(enumLine)

        inc(numTypes)

    inc(lineNumber)

  echo "Read details of ", numTypes, " types"


main()

