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

proc writeByte*(b: var Buffer, i: uint8 | byte | char) =
  b.buffer[b.writePos] = i
  inc(b.writePos)

proc writeInt32*(b: var Buffer, i: int32)=
  var sourceInt: int32 = i

  bigEndian32(addr b.buffer[b.writePos], addr sourceInt)
  inc(b.writePos, sizeof(int32))

proc writeInt16*(b: var Buffer, i: int16) =
  var sourceInt: int16 = i

  bigEndian16(addr b.buffer[b.writePos], addr sourceInt)
  inc(b.writePos, sizeof(int16))

proc writeString*(b: var Buffer, s: string) =
  for i in 0..high(s):
    b.buffer[b.writePos + i] = s[i]

  inc(b.writePos, len(s) + 1)

proc readChar*(b: var Buffer): char =
  result = b.buffer[b.readPos]
  inc(b.readPos)

proc readByte*(b: var Buffer): byte =
  result = byte(b.readByte())

proc readInt32*(b: var Buffer): int32 =
  var bigEndianVal = b.buffer[b.readPos..sizeof(int32)]
  inc(b.readPos, sizeof(int32))

  when system.cpuEndian == bigEndian:
    result = cast[int32](bigEndianVal)
  else:
    bigEndian32(addr result, addr bigEndianVal[0])
