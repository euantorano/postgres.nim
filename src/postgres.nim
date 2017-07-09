## A PostgreSQL client library for Nim.

import net, asyncdispatch, asyncnet, options

import postgres/private/[packets, buffer]

const
  DefaultPort* = Port(5432)

type
  ConnectionState {.pure.} = enum
    Disconnected,
    Startup,
    Connected

  PostgresClientBase[TSocket] = object of RootObj
    host: string
    port: Port
    sock: TSocket
    state: ConnectionState

  PostgresClient* = ref object of PostgresClientBase[net.Socket]

  AsyncPostgresClient* = ref object of PostgresClientBase[AsyncSocket]

proc newPostgresClient*(host = "localhost", port = DefaultPort): PostgresClient =
  result = PostgresClient(
    host: host,
    port: port,
    sock: newSocket(sockType = SOCK_STREAM, protocol = IPPROTO_TCP, buffered = true),
    state: ConnectionState.Disconnected
  )

proc newAsyncPostgresClient*(host = "localhost", port = DefaultPort): AsyncPostgresClient =
  result = AsyncPostgresClient(
    host: host,
    port: port,
    sock: newAsyncSocket(sockType = SOCK_STREAM, protocol = IPPROTO_TCP, buffered = true),
    state: ConnectionState.Disconnected
  )

proc readPacket(client: PostgresClient | AsyncPostgresClient): Future[Option[PostgresMessage]] {.multisync.} =
  # Packet header is a packet type (1 byte), followed by length (4 bytes)
  let packetHeader = await client.sock.recv(5)
  if len(packetHeader) < 5:
    return none(PostgresMessage)

  var buff = initBuffer(packetHeader)
  let packetType = buff.readChar()
  let packetLength = buff.readInt32() - 4

  let packetData = await client.sock.recv(packetLength)

  result = some(fromData(packetType, packetData))

proc open*(client: PostgresClient | AsyncPostgresClient, user = "postgres", database = "") {.multisync.} =
  await client.sock.connect(client.host, client.port)
  client.state = ConnectionState.Startup

  let startupMessage = initStartupMessage(user, database)
  let startupMessageString = $startupMessage
  await client.sock.send(startupMessageString)

  let readPacket = await client.readPacket()

  if isSome(readPacket):
    let packet = readPacket.get()

    # TODO: Check auth packet type and handle authentication

    if packet.isBackend and packet.backendMessageType == BackendMessageType.ErrorResponse:
      echo "Got error packet with error: ", packet.error
    else:
      echo "Received packet: ", repr(packet)
  else:
    echo "Connection closed by server"

proc close*(client: PostgresClient | AsyncPostgresClient) =
  if client.state != ConnectionState.Disconnected:
    client.sock.close()

when isMainModule:
  let conn = newPostgresClient()
  conn.open()
  echo "Opened connection!"

  defer: conn.close()
