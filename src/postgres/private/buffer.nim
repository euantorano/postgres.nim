## Buffer based upon a string, with methods to easily read/write postgres data types.

import endians

type
  Buffer* = object
    buffer: string
    writePos: int
    readPos: int

proc initBuffer*(len: int32): Buffer =
  result = Buffer(
    buffer: newString(len),
    writePos: 0,
    readPos: 0
  )

proc initBuffer*(initialData: string): Buffer =
  result = Buffer(
    buffer: initialData,
    writePos: len(initialData),
    readPos: 0,
  )

proc `$`*(b: Buffer): string =
  result = b.buffer

proc len*(b: Buffer): int =
  result = b.writePos

proc resizeBufferIfNeeded(b: var Buffer, spaceRequired: int) =
  if len(b.buffer) < (b.writePos + spaceRequired):
    setLen(b.buffer, b.writePos + spaceRequired)

proc writeByte*(b: var Buffer, i: uint8 | byte | char) =
  b.resizeBufferIfNeeded(sizeof(uint8))

  b.buffer[b.writePos] = i
  inc(b.writePos)

proc writeInt32*(b: var Buffer, i: int32)=
  b.resizeBufferIfNeeded(sizeof(int32))

  var sourceInt: int32 = i

  bigEndian32(addr b.buffer[b.writePos], addr sourceInt)
  inc(b.writePos, sizeof(int32))

proc writeInt16*(b: var Buffer, i: int16) =
  b.resizeBufferIfNeeded(sizeof(int16))

  var sourceInt: int16 = i

  bigEndian16(addr b.buffer[b.writePos], addr sourceInt)
  inc(b.writePos, sizeof(int16))

proc writeString*(b: var Buffer, s: string) =
  b.resizeBufferIfNeeded(len(s) + 1)

  for i in 0..high(s):
    b.buffer[b.writePos + i] = s[i]

  inc(b.writePos, len(s) + 1)

proc eof*(b: Buffer): bool =
  result = b.readPos >= len(b.buffer)

proc readChar*(b: var Buffer): char =
  result = b.buffer[b.readPos]
  inc(b.readPos)

proc readByte*(b: var Buffer): byte =
  result = byte(b.readChar())

proc readInt32*(b: var Buffer): int32 =
  var bigEndianVal = b.buffer[b.readPos..sizeof(int32)]
  inc(b.readPos, sizeof(int32))

  bigEndian32(addr result, addr bigEndianVal[0])

proc readString*(b: var Buffer): string =
  for i in b.readPos..high(b.buffer):
    if b.buffer[i] == '\0':
      result = b.buffer[b.readPos..i-1]
      b.readPos = i + 1
      return

proc readString*(b: var Buffer, strLen: int): string =
  result = b.buffer[b.readPos..b.readPos + (strLen - 1)]
  inc(b.readPos, strLen)
