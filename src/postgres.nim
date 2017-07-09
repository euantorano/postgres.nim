## A PostgreSQL client library for Nim.

import net, asyncdispatch, asyncnet, options

import postgres/private/[packets, buffer]

const
  DefaultPort* = Port(5432)

type
  ConnectionState {.pure.} = enum
    Disconnected,
    Startup,
    ReadyForQuery

  PostgresConnectionBase[TSocket] = object of RootObj
    host: string
    port: Port
    sock: TSocket
    state: ConnectionState
    transactionStatus: BackendTransactionStatus

  PostgresConnection* = ref object of PostgresConnectionBase[net.Socket]

  AsyncPostgresConnection* = ref object of PostgresConnectionBase[AsyncSocket]

  PostgresConnectionError* = ref object of Exception
    errorDetails: LogMessage

  UnsupportedAuthenticationTypeError* = object of Exception

  UnexpectedPacketError* = object of Exception

proc close*(client: PostgresConnection | AsyncPostgresConnection) =
  if client.state != ConnectionState.Disconnected:
    # TODO: send the close packet
    client.sock.close()
    client.state = ConnectionState.Disconnected

proc readPacket(client: PostgresConnection | AsyncPostgresConnection): Future[Option[PostgresMessage]] {.multisync.} =
  # Packet header is a packet type (1 byte), followed by length (4 bytes)
  let packetHeader = await client.sock.recv(5)
  if len(packetHeader) < 5:
    return none(PostgresMessage)

  var buff = initBuffer(packetHeader)
  let packetType = buff.readChar()
  let packetLength = buff.readInt32() - 4

  let packetData = await client.sock.recv(packetLength)

  result = some(fromData(packetType, packetData))

proc startup(conn: PostgresConnection | AsyncPostgresConnection, user: string, password: string, database: string) {.multisync.} =
  await conn.sock.connect(conn.host, conn.port)

  let startupMessage = initStartupMessage(user, database)
  let startupMessageString = $startupMessage
  await conn.sock.send(startupMessageString)

  var readPacket: Option[PostgresMessage]

  while true:
    readPacket = await conn.readPacket()

    if isSome(readPacket):
      let packet = readPacket.get()

      # TODO: Check auth packet type and handle authentication
      if packet.isBackend:
        case packet.backendMessageType
        of BackendMessageType.ErrorResponse:
          let err = PostgresConnectionError(
            errorDetails: packet.error,
            msg: "[" & $packet.error.code & "] " & packet.error.message
          )

          raise err
        of BackendMessageType.NoticeResponse:
          # TODO: How do we handle notices? Log?
          echo "Got notice: ", repr(packet)
        of BackendMessageType.AuthenticationRequest:
          case packet.authenticationType
          of AuthenticationType.Ok: discard # Nothing else needed
          of AuthenticationType.CleartextPassword:
            # TODO: send cleartext password
            discard
          of AuthenticationType.Md5Password:
            # TODO: Send MD5 password
            discard
          else:
            raise newException(UnsupportedAuthenticationTypeError, "Unsupported authentication type: " & $packet.authenticationType)
        of BackendMessageType.BackendKeyData:
          # TODO: save secret key data
          echo "Got backend key data: ", repr(packet)
        of BackendMessageType.ParameterStatus:
          # TODO: Save backend parameters
          echo "Got parameter status: ", repr(packet)
        of BackendMessageType.ReadyForQuery:
          # Startup complete, ready to start using connection
          echo "Ready for query: ", repr(packet)
          conn.state = ConnectionState.ReadyForQuery
          conn.transactionStatus = packet.backendTransactionStatus
          return
        else:
          raise newException(UnexpectedPacketError, "Received unexpected packet during startup of type: " & $packet.backendMessageType)
      else:
        raise newException(UnexpectedPacketError, "Received unexpected frontend error during startup")
    else:
      conn.close()
      return

proc open*(host = "localhost", port = DefaultPort, user = "postgres", password = "", database = ""): PostgresConnection =
  result = PostgresConnection(
    host: host,
    port: port,
    sock: newSocket(sockType = SOCK_STREAM, protocol = IPPROTO_TCP, buffered = true),
    state: ConnectionState.Startup,
    transactionStatus: BackendTransactionStatus.Idle
  )

  result.startup(user, password, database)

proc openAsync*(host = "localhost", port = DefaultPort, user = "postgres", password = "", database = ""): Future[AsyncPostgresConnection] {.async.} =
  result = AsyncPostgresConnection(
    host: host,
    port: port,
    sock: newAsyncSocket(sockType = SOCK_STREAM, protocol = IPPROTO_TCP, buffered = true),
    state: ConnectionState.Startup,
    transactionStatus: BackendTransactionStatus.Idle
  )

  await result.startup(user, password, database)

when isMainModule:
  let conn = open(user = "postgres", database = "docs_nimble_directory")
  echo "Opened connection!"

  defer: conn.close()
