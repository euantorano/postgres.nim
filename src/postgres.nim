## A PostgreSQL client library for Nim.

import net, asyncdispatch, asyncnet, options, strutils, tables

import postgres/private/[packets, buffer]

export packets

const
  DefaultPort* = Port(5432)
    ## The default port to connect to a PostgreSQL server.

type
  ConnectionState {.pure.} = enum
    Disconnected,
    Startup,
    ReadyForQuery,
    InQuery,
    ReadingRows,
    PreparingStatement

  NoticeCallbackFunction* = proc(notice: PostgresMessage) {.gcsafe.}
    ## Callback function to handle any notice messages sent by the Postgres server.

  PostgresConnectionBase[TSocket] = ref object of RootObj
    host: string
    port: Port
    sock: TSocket
    state: ConnectionState
    backendProcessId: int32
    backendSecretKey: int32
    transactionStatus: BackendTransactionStatus
    noticeCallback: NoticeCallbackFunction

  PostgresConnection* = ref object of PostgresConnectionBase[net.Socket]
    ## A synchronous connection to a PostgreSQL server.

  AsyncPostgresConnection* = ref object of PostgresConnectionBase[AsyncSocket]
    ## An asynchronous connection to a PostgreSQL server.

  PostgresReaderBase[TConnection] = object of RootObj
    connection: TConnection
    fieldNamesToIndexes: TableRef[string, int]
      ## Maps field names to their positions
    numRows*: BiggestInt
    isComplete*: bool
    currentRow: Option[PostgresMessage]
    ## TODO: Map of fields to their types

  PostgresReader* = ref object of PostgresReaderBase[PostgresConnection]

  AsyncPostgresReader* = ref object of PostgresReaderBase[AsyncPostgresConnection]

  PreparedStatement* = object
    name: string
    query: string

  ConnectionClosedError* = object of IOError
    ## Error thrown when the connectin to the PostgreSQL server is detected to have been closed by the server.

  PostgresCommandError* = ref object of Exception
    ## Error thrown when an error message is received from the PostgreSQL server.
    errorDetails*: LogMessage
      ## Details about the error.

  UnsupportedAuthenticationTypeError* = object of Exception
    ## Error thrown when the PostgreSQL server requests authentication using an unsupported authentication type.
    ##
    ## Currently supported authentication types are:
    ## - None
    ## - Plaintext Password
    ## - MD5 Password

  UnexpectedPacketError* = object of Exception
    ## Error thrown when an unexpected packet is received from the PostgreSQL server.

  InvalidStateError* = object of Exception
    ## Error thrown when the connection is determined to be in an invalid state whilst attempting a command.

  UnknownColumnError* = object of Exception
    ## Error thrown when an unknown column is attempted to be retrieved from a reader.

proc close*(client: PostgresConnection | AsyncPostgresConnection) {.multisync.} =
  ## Close the connection to the PostgreSQL server, sending a terminate message to close gracefully.
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
        of BackendMessageType.Unknown:
          raise newException(UnexpectedPacketError, "Received unknown packet during startup with identifier: " & $packet.messageTypeIdentifier)
        else:
          raise newException(UnexpectedPacketError, "Received unexpected packet during startup of type: " & $packet.backendMessageType)
      else:
        raise newException(UnexpectedPacketError, "Received unexpected frontend packet during startup")
    else:
      await conn.close()
      raise newException(ConnectionClosedError, "Connection to server lost during startup")

proc open*(host = "localhost", port = DefaultPort, user = "postgres", password = "", database = "", noticeCallback: NoticeCallbackFunction = nil): PostgresConnection =
  ## Open a synchronous connection to the given PostgreSQL server.
  ##
  ## You may pass a `noticeCallback`, which will be invoked whenever a notice is received frm the server.
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
  ## Open an asynchronous connection to the given PostgreSQL server.
  ##
  ## You may pass a `noticeCallback`, which will be invoked whenever a notice is received frm the server.
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
  checkState(conn, ConnectionState.ReadyForQuery, "Cannot execute command whilst in state: ")

  let queryMessage = initQuerymessage(query)
  await conn.sock.send($queryMessage)

  conn.state = ConnectionState.InQuery

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
        of BackendMessageType.RowDescription: discard
        of BackendMessageType.ParameterDescription: discard
        of BackendMessageType.DataRow: discard
        of BackendMessageType.ReadyForQuery:
          # We always get a ready for query packet to end the query - even if there was an error
          conn.state = ConnectionState.ReadyForQuery
          break
        of BackendMessageType.Unknown:
          raise newException(UnexpectedPacketError, "Received unknown packet during query with identifier: " & $packet.messageTypeIdentifier)
        else:
          raise newException(UnexpectedPacketError, "Received unexpected packet during query of type: " & $packet.backendMessageType)
      else:
        raise newException(UnexpectedPacketError, "Received unexpected frontend packet during ")
    else:
      await conn.close()
      raise newException(ConnectionClosedError, "Connection to server lost during query")

proc query*(conn: PostgresConnection | AsyncPostgresConnection, query: string): Future[PostgresReader | AsyncPostgresReader] {.multisync.} =
  ## Run an SQL query with no parameters against the connection.
  ##
  ## Returns a reader that lets you read the result of the query. The reader should then be ran in a loop reading rows.
  ##
  ## If not all rows are read from the result set, you should close the reader. If all rows are read (eg: `read()` returns false), the reader is closed automatically.
  ##
  ## Updates, inserts and any other queries with values should use the other versions of this procedure that take a list of parameters.
  checkState(conn, ConnectionState.ReadyForQuery, "Cannot execute command whilst in state: ")

  let queryMessage = initQuerymessage(query)
  await conn.sock.send($queryMessage)

  conn.state = ConnectionState.InQuery

  when conn is PostgresConnection:
    result = PostgresReader(
      connection: conn,
      fieldNamesToIndexes: nil,
      isComplete: false,
      currentRow: none(PostgresMessage)
    )
  else:
    result = AsyncPostgresReader(
      connection: conn,
      fieldNamesToIndexes: nil,
      isComplete: false,
      currentRow: none(PostgresMessage)
    )

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
              tryParseNumRows(packet.commandTag, 9, hasNumRows, result.numRows)
            elif len(packet.commandTag) > 7 and packet.commandTag[0..5] == "DELETE":
              tryParseNumRows(packet.commandTag, 7, hasNumRows, result.numRows)
            elif len(packet.commandTag) > 7 and packet.commandTag[0..5] == "UPDATE":
              tryParseNumRows(packet.commandTag, 7, hasNumRows, result.numRows)
            elif len(packet.commandTag) > 7 and packet.commandTag[0..5] == "SELECT":
              tryParseNumRows(packet.commandTag, 7, hasNumRows, result.numRows)
            elif len(packet.commandTag) > 5 and packet.commandTag[0..3] == "MOVE":
              tryParseNumRows(packet.commandTag, 5, hasNumRows, result.numRows)
            elif len(packet.commandTag) > 6 and packet.commandTag[0..4] == "FETCH":
              tryParseNumRows(packet.commandTag, 6, hasNumRows, result.numRows)
            elif len(packet.commandTag) > 5 and packet.commandTag[0..3] == "COPY":
              tryParseNumRows(packet.commandTag, 5, hasNumRows, result.numRows)
        of BackendMessageType.EmptyQueryResponse: discard # Empty query, no need to do anything
        of BackendMessageType.ErrorResponse:
          error = some(packet)
        of BackendMessageType.NoticeResponse:
          if not isNil(conn.noticeCallback):
            conn.noticeCallback(packet)
        of BackendMessageType.RowDescription:
          var idx: int = 0

          result.fieldNamesToIndexes = newTable[string, int](rightSize(packet.numFieldsInRow))

          for field in packet.fields:
            result.fieldNamesToIndexes.add(field.fieldName, idx)
            inc(idx)

          # Next come the data rows
          conn.state = ConnectionState.ReadingRows
          break
        of BackendMessageType.ReadyForQuery:
          # We always get a ready for query packet to end the query - even if there was an error
          conn.state = ConnectionState.ReadyForQuery
          result.isComplete = true
          break
        of BackendMessageType.Unknown:
          raise newException(UnexpectedPacketError, "Received unknown packet during query with identifier: " & $packet.messageTypeIdentifier)
        else:
          raise newException(UnexpectedPacketError, "Received unexpected packet during query of type: " & $packet.backendMessageType)
      else:
        raise newException(UnexpectedPacketError, "Received unexpected frontend packet during query")
    else:
      await conn.close()
      raise newException(ConnectionClosedError, "Connection to server lost during query")

  if isSome(error):
    let errPacket = error.get()
    raise PostgresCommandError(
      errorDetails: errPacket.error,
      msg: "[" & $errPacket.error.code & "] " & errPacket.error.message
    )

proc read*(reader: PostgresReader | AsyncPostgresReader): Future[bool] {.multisync.} =
  ## Read the next from from the result set.
  ##
  ## Returns true if a row was read. If the end of the result set is reached, returns false.
  ##
  ## Columns from the row can be read if the row is read successfully.
  if reader.isComplete:
    return false

  var
    readPacket: Option[PostgresMessage]

  while true:
    readPacket = await reader.connection.readPacket()

    if isSome(readPacket):
      let packet = readPacket.get()

      if packet.isBackend:
        case packet.backendMessageType
        of BackendMessageType.DataRow:
          reader.currentRow = some(packet)

          return true
        of BackendMessageType.CommandComplete: discard
        of BackendMessageType.ReadyForQuery:
          reader.isComplete = true
          reader.connection.state = ConnectionState.ReadyForQuery

          return false

        of BackendMessageType.ErrorResponse:
          raise PostgresCommandError(
            errorDetails: packet.error,
            msg: "[" & $packet.error.code & "] " & packet.error.message
          )
        of BackendMessageType.NoticeResponse:
          if not isNil(reader.connection.noticeCallback):
            reader.connection.noticeCallback(packet)
        else:
          raise newException(UnexpectedPacketError, "Received unexpected packet whilst reading row of type: " & $packet.backendMessageType)
      else:
        raise newException(UnexpectedPacketError, "Received unexpected frontend packet whilst reading row")
    else:
      await reader.connection.close()
      raise newException(ConnectionClosedError, "Connection to server lost whilst reading row")

proc close*(reader: PostgresReader | AsyncPostgresReader) {.multisync.} =
  ## Close the reader, putting the connection back into a state ready to run another query.
  if reader.isComplete:
    return

  var
    readPacket: Option[PostgresMessage]
    error: Option[PostgresMessage] = none(PostgresMessage)

  while true:
    readPacket = await reader.connection.readPacket()

    if isSome(readPacket):
      let packet = readPacket.get()

      if packet.isBackend:
        case packet.backendMessageType
        of BackendMessageType.DataRow: discard
        of BackendMessageType.CommandComplete: discard
        of BackendMessageType.ReadyForQuery:
          reader.isComplete = true
          reader.connection.state = ConnectionState.ReadyForQuery

          break
        of BackendMessageType.ErrorResponse:
          error = some(packet)
        of BackendMessageType.NoticeResponse:
          if not isNil(reader.connection.noticeCallback):
            reader.connection.noticeCallback(packet)
        else: discard
      else:
        raise newException(UnexpectedPacketError, "Received unexpected frontend packet whilst closing reader")
    else:
      await reader.connection.close()
      raise newException(ConnectionClosedError, "Connection to server lost whilst closing reader")

  if isSome(error):
    let errPacket = error.get()
    raise PostgresCommandError(
      errorDetails: errPacket.error,
      msg: "[" & $errPacket.error.code & "] " & errPacket.error.message
    )

# TODO: Don't always return a string - use Postgres data types
proc `[]`*(reader: PostgresReader | AsyncPostgresReader, columnName: string): string =
  ## Get a column's value by name from the current row.
  if reader.isComplete:
    raise newException(InvalidStateError, "Reader has already been completed, cannot get column value")

  if isNil(reader.fieldNamesToIndexes):
    raise newException(InvalidStateError, "Reader cannot map field names to indexes, as now row descrition message was received from the server")

  if isNone(reader.currentRow):
    raise newException(InvalidStateError, "Reader must read a row before getting a column value")

  if not reader.fieldNamesToIndexes.hasKey(columnName):
    raise newException(UnknownColumnError, "Unknown column: " & columnName)

  let idx = reader.fieldNamesToIndexes[columnName]
  let currentRow = reader.currentRow.get()
  if len(currentRow.columns) - 1 < idx:
    raise newException(UnknownColumnError, "Unknown column: " & columnName)

  result = currentRow.columns[idx]

proc `[]`*(reader: PostgresReader | AsyncPostgresReader, index: int): string =
  ## Get a column's value by index from the current row.
  if reader.isComplete:
    raise newException(InvalidStateError, "Reader has already been completed, cannot get column value")

  if isNone(reader.currentRow):
    raise newException(InvalidStateError, "Reader must read a row before getting a column value")

  let currentRow = reader.currentRow.get()
  if len(currentRow.columns) - 1 < index:
    raise newException(UnknownColumnError, "Unknown column with index: " & $index)

  result = currentRow.columns[index]

proc inTransaction*(conn: PostgresConnection | AsyncPostgresConnection): bool =
  ## Determine whether the connection is currently in a transaction.
  result = conn.transactionStatus != BackendTransactionStatus.Idle

proc prepare*(conn: PostgresConnection | AsyncPostgresConnection, query: string, name: string = ""): Future[PreparedStatement] {.multisync.} =
  ## Prepare a query to execute on the connection.
  ##
  ## The prepared statement will know what type of parameters it takes and what type of result set will be returned.
  ##
  ## You should then `bind` some parameters to the statement and execute it.
  checkState(conn, ConnectionState.ReadyForQuery, "Cannot execute command whilst in state: ")

  result = PreparedStatement(
    name: name,
    query: query
  )

  let parseMessage = initParseMessage(name = name, query = query)
  await conn.sock.send($parseMessage)

  let describeMessage = initDescribeMessage(DescribeType.PreparedStatement, name)
  await conn.sock.send($describeMessage)

  let syncMessage = initSyncMessage()
  await conn.sock.send($syncMessage)

  conn.state = ConnectionState.PreparingStatement

  var
    readPacket: Option[PostgresMessage]

  while true:
    readPacket = await conn.readPacket()

    if isSome(readPacket):
      let packet = readPacket.get()

      if packet.isBackend:
        case packet.backendMessageType
        of BackendMessageType.ErrorResponse:
          raise PostgresCommandError(
            errorDetails: packet.error,
            msg: "[" & $packet.error.code & "] " & packet.error.message
          )
        of BackendMessageType.ParseComplete: discard
        of BackendMessageType.ParameterDescription: discard
        of BackendMessageType.RowDescription: discard
        of BackendMessageType.ReadyForQuery:
          conn.state = ConnectionState.ReadyForQuery
          break
        of BackendMessageType.Unknown:
          raise newException(UnexpectedPacketError, "Received unknown packet during prepare with identifier: " & $packet.messageTypeIdentifier)
        else:
          raise newException(UnexpectedPacketError, "Received unexpected packet whilst parsing statement of type: " & $packet.backendMessageType)
      else:
        raise newException(UnexpectedPacketError, "Received unexpected frontend packet during query")
