## A PostgreSQL client library for Nim.

import net, asyncdispatch, asyncnet, options, strutils

import postgres/private/[packets, buffer]

const
  DefaultPort* = Port(5432)

type
  ConnectionState {.pure.} = enum
    Disconnected,
    Startup,
    ReadyForQuery,
    QueryInProgress

  NoticeCallbackFunction* = proc(notice: PostgresMessage) {.gcsafe.}
    ## Callback function to handle any notice messages sent by the Postgres server.

  PostgresConnectionBase[TSocket] = object of RootObj
    host: string
    port: Port
    sock: TSocket
    state: ConnectionState
    backendProcessId: int32
    backendSecretKey: int32
    transactionStatus: BackendTransactionStatus
    noticeCallback: NoticeCallbackFunction

  PostgresConnection* = ref object of PostgresConnectionBase[net.Socket]

  AsyncPostgresConnection* = ref object of PostgresConnectionBase[AsyncSocket]

  ConnectionClosedError* = object of IOError

  PostgresCommandError* = ref object of Exception
    errorDetails: LogMessage

  UnsupportedAuthenticationTypeError* = object of Exception

  UnexpectedPacketError* = object of Exception

  InvalidStateError* = object of Exception

proc close*(client: PostgresConnection | AsyncPostgresConnection) {.multisync.} =
  if client.state != ConnectionState.Disconnected:
    try:
      let terminateMessage = initTerminateMessage()
      await client.sock.send($terminateMessage)
    except: discard # ignore any errors sending the terminate command

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
  await conn.sock.send($startupMessage)

  var readPacket: Option[PostgresMessage]

  while true:
    readPacket = await conn.readPacket()

    if isSome(readPacket):
      let packet = readPacket.get()

      if packet.isBackend:
        case packet.backendMessageType
        of BackendMessageType.ErrorResponse:
          await conn.close()

          raise PostgresCommandError(
            errorDetails: packet.error,
            msg: "[" & $packet.error.code & "] " & packet.error.message
          )
        of BackendMessageType.NoticeResponse:
          if not isNil(conn.noticeCallback):
            conn.noticeCallback(packet)
        of BackendMessageType.AuthenticationRequest:
          case packet.authenticationType
          of AuthenticationType.Ok: discard # Nothing else needed
          of AuthenticationType.CleartextPassword:
            let passwordMessage = initCleartextPasswordMessage(password)
            await conn.sock.send($passwordMessage)
          of AuthenticationType.Md5Password:
            let passwordMessage = initMd5PasswordMessage(password, user, packet.salt)
            await conn.sock.send($passwordMessage)
          else:
            raise newException(UnsupportedAuthenticationTypeError, "Unsupported authentication type: " & $packet.authenticationType)
        of BackendMessageType.BackendKeyData:
          conn.backendProcessId = packet.processId
          conn.backendSecretKey = packet.secretKey
        of BackendMessageType.ParameterStatus:
          # TODO: Save backend parameters?
          discard
        of BackendMessageType.ReadyForQuery:
          conn.state = ConnectionState.ReadyForQuery
          conn.transactionStatus = packet.backendTransactionStatus
          return
        else:
          raise newException(UnexpectedPacketError, "Received unexpected packet during startup of type: " & $packet.backendMessageType)
      else:
        raise newException(UnexpectedPacketError, "Received unexpected frontend packet during startup")
    else:
      await conn.close()
      raise newException(ConnectionClosedError, "Connection to server lost during startup")

proc open*(host = "localhost", port = DefaultPort, user = "postgres", password = "", database = "", noticeCallback: NoticeCallbackFunction = nil): PostgresConnection =
  result = PostgresConnection(
    host: host,
    port: port,
    sock: newSocket(sockType = SOCK_STREAM, protocol = IPPROTO_TCP, buffered = true),
    state: ConnectionState.Startup,
    transactionStatus: BackendTransactionStatus.Idle,
    noticeCallback: noticeCallback
  )

  result.startup(user, password, database)

proc openAsync*(host = "localhost", port = DefaultPort, user = "postgres", password = "", database = "", noticeCallback: NoticeCallbackFunction = nil): Future[AsyncPostgresConnection] {.async.} =
  result = AsyncPostgresConnection(
    host: host,
    port: port,
    sock: newAsyncSocket(sockType = SOCK_STREAM, protocol = IPPROTO_TCP, buffered = true),
    state: ConnectionState.Startup,
    transactionStatus: BackendTransactionStatus.Idle,
    noticeCallback: noticeCallback
  )

  await result.startup(user, password, database)

template checkState(conn: PostgresConnection | AsyncPostgresConnection, expectedState: ConnectionState, message: string) =
  if conn.state != expectedState:
    raise newException(InvalidStateError, message & $conn.state)

template tryParseNumRows(data: string, fromIdx: int, success: var bool, dest: var BiggestInt) =
  try:
    dest = parseBiggestInt(data[fromIdx..len(data) - 1])
    success = true
  except:
    dest = 0
    success = false

proc execute*(conn: PostgresConnection | AsyncPostgresConnection, query: string): Future[BiggestInt] {.multisync, discardable.} =
  ## Run an SQL query with no parameters against the connection.
  ##
  ## Returns the number of rows affected by the query. In the case that the query contains multiple commands, only the number of rows affected by the first command will be returned.
  ##
  ## Updates, inserts and any other queries with values should use the other versions of this procedure that take a list of parameters.
  checkState(conn, ConnectionState.ReadyForQuery, "Cannot run query whilst in state: ")

  let queryMessage = initQuerymessage(query)
  conn.state = ConnectionState.QueryInProgress
  await conn.sock.send($queryMessage)

  var
    readPacket: Option[PostgresMessage]
    error: Option[PostgresMessage] = none(PostgresMessage)
    hasNumRows = false

  while true:
    readPacket = await conn.readPacket()

    if isSome(readPacket):
      let packet = readPacket.get()

      if packet.isBackend:
        case packet.backendMessageType
        of BackendMessageType.CommandComplete:
          if len(packet.commandTag) > 0 and not hasNumRows:
            # Check that the command tag is a command tag that has rows
            if len(packet.commandTag) > 9 and packet.commandTag[0..5] == "INSERT":
              tryParseNumRows(packet.commandTag, 9, hasNumRows, result)
            elif len(packet.commandTag) > 7 and packet.commandTag[0..5] == "DELETE":
              tryParseNumRows(packet.commandTag, 7, hasNumRows, result)
            elif len(packet.commandTag) > 7 and packet.commandTag[0..5] == "UPDATE":
              tryParseNumRows(packet.commandTag, 7, hasNumRows, result)
            elif len(packet.commandTag) > 7 and packet.commandTag[0..5] == "SELECT":
              tryParseNumRows(packet.commandTag, 7, hasNumRows, result)
            elif len(packet.commandTag) > 5 and packet.commandTag[0..3] == "MOVE":
              tryParseNumRows(packet.commandTag, 5, hasNumRows, result)
            elif len(packet.commandTag) > 6 and packet.commandTag[0..4] == "FETCH":
              tryParseNumRows(packet.commandTag, 6, hasNumRows, result)
            elif len(packet.commandTag) > 5 and packet.commandTag[0..3] == "COPY":
              tryParseNumRows(packet.commandTag, 5, hasNumRows, result)
        of BackendMessageType.EmptyQueryResponse: discard # Empty query, no need to do anything
        of BackendMessageType.ErrorResponse:
          error = some(packet)
        of BackendMessageType.NoticeResponse:
          if not isNil(conn.noticeCallback):
            conn.noticeCallback(packet)
        of BackendMessageType.ReadyForQuery:
          # We always get a ready for query packet to end the query - even if there was an error
          break
        else:
          raise newException(UnexpectedPacketError, "Received unexpected packet during query of type: " & $packet.backendMessageType)
      else:
        raise newException(UnexpectedPacketError, "Received unexpected frontend packet during startup")
    else:
      await conn.close()
      raise newException(ConnectionClosedError, "Connection to server lost during query")

  conn.state = ConnectionState.ReadyForQuery
  if isSome(error):
    let errPacket = error.get()
    raise PostgresCommandError(
      errorDetails: errPacket.error,
      msg: "[" & $errPacket.error.code & "] " & errPacket.error.message
    )

when isMainModule:
  proc logNotice(notice: PostgresMessage) =
    echo "Received notice from server: [", notice.notice.code, "] ", notice.notice.message

  let conn = open(host = "localhost", user = "postgres", password = "password", database = "test", noticeCallback = logNotice)
  defer: conn.close()
  echo "Opened connection!"

  conn.execute("CREATE TABLE IF NOT EXISTS users (id serial PRIMARY KEY, name varchar(255) NOT NULL, age integer NOT NULL);")
  echo "Created users table!"

  let numRowsInsert = conn.execute("INSERT INTO users (name, age) VALUES ('euan', 1);")
  echo "Inserted ", numRowsInsert, " rows into the users table"

  let numRowsDelete = conn.execute("DELETE FROM users WHERE name = 'euan';")
  echo "Deleted ", numRowsDelete, " rows from the users table"
