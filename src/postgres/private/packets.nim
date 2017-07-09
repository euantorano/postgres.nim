## Packet types and utility functions to read/write them.

from strutils import parseInt

import ./buffer

const
  DefaultProtocolVersionNumber = 196608'i32
    ## The default protocol version number. The most significant 16 bits are the major version number (3). The least significant 16 bits are the minor version number (0).

type
  FrontEndMessageType* {.pure.} = enum
    Startup = '\0',
      ## For legacy reasons the startup message type doesn't have a start byte.
    Bind = 'B',
      ## Identifies the message as a Bind command.
    Close = 'C',
      ## Identifies the message as a Close command.
    Describe = 'D',
      ## Identifies the message as a Describe command.
    Execute = 'E',
      ## Identifies the message as an Execute command.
    FunctionCall = 'F',
      ## Identifies the message as a function call.
    Flush = 'H',
      ## Identifies the message as a Flush command.
    Parse = 'P',
      ## Identifies the message as a Parse command.
    Query = 'Q',
      ## Identifies the message as a simple query.
    Sync = 'S'
      ## Identifies the message as a Sync command.
    Terminate = 'X',
      ## Identifies the message as a termination.
    CopyDone = 'c'
      ## Identifies the message as a COPY-complete indicator.
    CopyData = 'd'
      ## Identifies the message as COPY data.
    CopyFail = 'f'
      ## Identifies the message as a COPY-failure indicator.
    PasswordMessage = 'p',
      ## Identifies the message as a password response. Note that this is also used for GSSAPI and SSPI response messages (which is really a design error, since the contained data is not a null-terminated string in that case, but can be arbitrary binary data).

  BackendMessageType* {.pure.} = enum
    Unknown = 0,
      ## Unknown backend message type.
      ##
      ## This is only required for the object variant to work.
    ParseComplete = '1',
      ## Identifies the message as a Parse-complete indicator.
    BindComplete = '2',
      ## Identifies the message as a Bind-complete indicator.
    CloseComplete = '3',
      ## Identifies the message as a Close-complete indicator.
    NotificationResponse = 'A',
      ## Identifies the message as a notification response.
    CommandComplete = 'C'
      ## Identifies the message as a command-completed response.
    DataRow = 'D',
      ## Identifies the message as a data row.
    ErrorResponse = 'E',
      ## Identifies the message as an error.
    CopyInResponse = 'G'
      ## Identifies the message as a Start Copy In response. The frontend must now send copy-in data (if not prepared to do so, send a CopyFail message).
    CopyOutResponse = 'H',
      ## Identifies the message as a Start Copy Out response. This message will be followed by copy-out data.
    EmptyQueryResponse = 'I',
      ## Identifies the message as a response to an empty query string. (This substitutes for CommandComplete.).
    BackendKeyData = 'K'
      ## Identifies the message as cancellation key data. The frontend must save these values if it wishes to be able to issue CancelRequest messages later.
    NoticeResponse = 'N',
      ## Identifies the message as a notice.
    AuthenticationRequest = 'R',
      ## Identifies the message as an authentication request.
    ParameterStatus ='S',
      ## Identifies the message as a run-time parameter status report.
    RowDescription = 'T',
      ## Identifies the message as a row description.
    FunctionCallResponse = 'V',
      ## Identifies the message as a function call result.
    CopyBothResponse = 'W',
      ## Identifies the message as a Start Copy Both response. This message is used only for Streaming Replication.
    ReadyForQuery = 'Z',
      ## Identifies the message type. ReadyForQuery is sent whenever the backend is ready for a new query cycle.
    CopyDone = 'c'
      ## Identifies the message as a COPY-complete indicator.
    CopyData = 'd'
      ## Identifies the message as COPY data.
    NoData = 'n',
      ## Identifies the message as a no-data indicator.
    PortalSuspended = 's',
      ## Identifies the message as a portal-suspended indicator. Note this only appears if an Execute message's row-count limit was reached.
    ParameterDescription = 't',
      ## Identifies the message as a parameter description.

  AuthenticationType* {.pure.} = enum
    Ok = 0,
      ## Specifies that the authentication was successful.
    KerberosV5 = 2,
      ## Specifies that Kerberos V5 authentication is required.
    CleartextPassword = 3,
      ## Specifies that a clear-text password is required.
    Md5Password = 5,
      ## Specifies that an MD5-encrypted password is required.
    ScmCredential = 6,
      ## Specifies that an SCM credentials message is required.
    GssApi = 7,
      ## Specifies that GSSAPI authentication is required.
    GssApiOrSppiData = 8,
      ## Specifies that this message contains GSSAPI or SSPI data.
    Sppi = 9
      ## Specifies that SSPI authentication is required.

  FormatCode* {.pure.} = enum
    Text = 0'i16,
    Binary = 1'i16

  CloseMessageType* {.pure.} = enum
    ClosePortal = 'p'
      ## Close a portal.
    ClosePreparedStatement = 's'
      ## Close a prepared statement.

  CopyFormat* {.pure.} = enum
    Textual = 0,
      ## 0 indicates the overall COPY format is textual (rows separated by newlines, columns separated by separator characters, etc).
    Binary = 1
      ## 1 indicates the overall copy format is binary (similar to DataRow format).

  DescribeType* {.pure.} = enum
    Portal = 'p'
      ## 'P' to describe a portal.
    PreparedStatement = 's',
      ## 'S' to describe a prepared statement.

  BackendTransactionStatus* {.pure.} = enum
    InFailedTransactionBlock = 'E'
      ## 'E' if in a failed transaction block (queries will be rejected until block is ended).
    Idle = 'I',
      ## 'I' if idle (not in a transaction block).
    InTransactionBlock = 'T'
      ## 'T' if in a transaction block.

  Field* = object
    fieldName: string
    tableObjectId: int32
    columnAttributeNumber: int16
    dataType: int32
    dataTypeSize: int16
    dataTypeModifier: int32
    formatCode: FormatCode

  LogMessageSeverity* {.pure.} = enum
    Error = "ERROR",
    Fatal = "FATAL",
    Panic = "PANIC",
    Warning = "WARNING",
    Notice = "NOTICE",
    Debug = "DEBUG",
    Info = "INFO",
    Log = "LOG"

  LogMessage* = object
    severity*: LogMessageSeverity
    code*: string
    message*: string
    detail*: string
    hint*: string
    position*: int
    internalPosition*: int
    internalQuery*: string
    where*: string
    schema*: string
    table*: string
    columnName*: string
    dataTypeName*: string
    constraintName*: string
    file*: string
    line*: int
    routine*: string

  PostgresMessage* = object
    case isBackend*: bool
    of true:
      case backendMessageType*: BackendMessageType
      of BackendMessageType.AuthenticationRequest:
        authenticationType*: AuthenticationType
      of BackendMessageType.BackendKeyData:
        processId*: int32
        secretKey*: int32
      of BackendMessageType.BindComplete: nil
      of BackendMessageType.CloseComplete: nil
      of BackendMessageType.CommandComplete:
        commandTag*: string
      of BackendMessageType.CopyData:
        data: string
      of BackendMessageType.CopyDone: nil
      of BackendMessageType.CopyInResponse:
        copyInFormat: CopyFormat
        numColumnsToCopyIn: int16
        copyInFormatCodes: seq[FormatCode]
      of BackendMessageType.CopyOutResponse:
        copyOutFormat: CopyFormat
        numColumnsToCopyOut: int16
        copyOutFormatCodes: seq[FormatCode]
      of BackendMessageType.CopyBothResponse:
        copyBothFormat: CopyFormat
        numColumnsToCopyBoth: int16
        copyBothFormatCodes: seq[FormatCode]
      of BackendMessageType.DataRow:
        numColumns: int16
        columns: seq[string]
      of BackendMessageType.EmptyQueryResponse: nil
      of BackendMessageType.ErrorResponse:
        error*: LogMessage
      of BackendMessageType.FunctionCallResponse:
        functionCallResultLength: int32
        functionCallResult: string
      of BackendMessageType.NoData: nil
      of BackendMessageType.NoticeResponse:
        notice*: LogMessage
      of BackendMessageType.NotificationResponse:
        notifyingProcessId: int32
        notifyChannelName: string
        notifyPayload: string
      of BackendMessageType.ParameterDescription:
        parameterDesccriptionCount: int16
        parameterDataTypeObjectIds: seq[int16]
      of BackendMessageType.ParameterStatus:
        parameterName*: string
        parameterValue*: string
      of BackendMessageType.ParseComplete: nil
      of BackendMessageType.PortalSuspended: nil
      of BackendMessageType.ReadyForQuery:
        backendTransactionStatus*: BackendTransactionStatus
      of BackendMessageType.RowDescription:
        numFieldsInRow: int16
        fields: seq[Field]
      else: nil
    of false:
      case frontendMessageType*: FrontEndMessageType
      of FrontEndMessageType.Startup:
        protocolVersionNumber: int32
        user: string
        database: string
      of FrontEndMessageType.Bind:
        destinationPortal: string
        sourcePreparedStatement: string
        numParameterFormatCodes: int16
        bindParameterFormatCodes: seq[FormatCode]
        numBindParameterValues: int16
        bindParameters: seq[string]
        numResultColumnFormatCodes: int16
        bindResultColumnFormatCode: seq[FormatCode]
      of FrontEndMessageType.Close:
        closeType: CloseMessageType
      of FrontEndMessageType.Describe:
        describeType: DescribeType
        nameToDescribe: string
      of FrontEndMessageType.Execute:
        portalToExecute: string
        maxRowsToFormat: int32
      of FrontEndMessageType.FunctionCall:
        functionObjectId: int32
        numArgFormatCodes: int16
        functionArgFormatCodes: seq[FormatCode]
        numFunctionArgs: int16
        functionArgs: seq[string]
        functionResultFormatCode: FormatCode
      of FrontEndMessageType.Flush: nil
      of FrontEndMessageType.Parse:
        parseDestinationFormatStringName: string
        parseQueryString: string
        parseParameterDataTypesLen: int16
        parseParameterDataTypeObjectIds: seq[int16]
      of FrontEndMessageType.Query:
        query: string
      of FrontEndMessageType.Sync: nil
      of FrontEndMessageType.Terminate: nil
      of FrontEndMessageType.CopyDone: nil
      of FrontEndMessageType.CopyData:
        dataToCopy: string
      of FrontEndMessageType.CopyFail:
        errorMessage: string
      of FrontEndMessageType.PasswordMessage:
        password: string
      else: nil

  PacketParseError* = object of Exception

proc initStartupMessage*(user = "postgres", database = ""): PostgresMessage =
  result = PostgresMessage(
    isBackend: false,
    frontEndMessageType: FrontEndMessageType.Startup,
    protocolVersionNumber: DefaultProtocolVersionNumber,
    user: user,
    database: database
  )

proc startupMessageToString(m: PostgresMessage, dest: var string) {.inline.} =
  # 4 bytes for packet length (int32), 4 bytes for protocol version (int32), then parameters, then a null terminator
  let packetLen = int32(9 + (if len(m.user) > 0: len(m.user) + 6 else: 0) + (if len(m.database) > 0: len(m.database) + 10 else: 0))
  var buff = initBuffer(packetLen)

  buff.writeInt32(packetLen)
  buff.writeInt32(m.protocolVersionNumber)

  if len(m.user) > 0:
    buff.writeString("user")
    buff.writeString(m.user)

  if len(m.database) > 0:
    buff.writeString("database")
    buff.writeString(m.database)

  dest = $buff

proc initQueryMessage*(query: string): PostgresMessage =
  result = PostgresMessage(
    isBackend: false,
    frontEndMessageType: FrontEndMessageType.Query,
    query: query
  )

proc queryMessageToString(m: PostgresMessage, dest: var string) {.inline.} =
  let packetLen = int32(4 + len(m.query) + 1)
  var buff = initBuffer(packetlen + 1)

  buff.writeByte(char(FrontEndMessageType.Query))
  buff.writeInt32(packetLen)
  buff.writeString(m.query)

  dest = $buff

proc initTerminateMessage*(): PostgresMessage =
  result = PostgresMessage(
    isBackend: false,
    frontEndMessageType: FrontEndMessageType.Terminate
  )

proc terminateMessageToString(m: PostgresMessage, dest: var string) {.inline.} =
  var buff = initBuffer(5)
  buff.writeByte(char(FrontEndMessageType.Terminate))
  buff.writeint32(4)

  dest = $buff

proc `$`*(m: PostgresMessage): string =
  if not m.isBackend:
    case m.frontEndMessageType
    of FrontEndMessageType.Startup:
      startupMessageToString(m, result)
    of FrontEndMessageType.Query:
      queryMessageToString(m, result)
    of FrontEndMessageType.Terminate:
      terminateMessageToString(m, result)
    else:
      result = ""
  else:
    result = ""

proc parseLogMessageFields(data: string): LogMessage {.inline.} =
  result = LogMessage()

  var
    buff = initBuffer(data)
    currentCode: char
    currentMessage: string

  while not buff.eof():
    currentCode = buff.readChar()
    currentMessage = buff.readString()

    case currentCode
      of 'S':
        case currentMessage
        of "ERROR":
          result.severity = LogMessageSeverity.Error
        of "FATAL":
          result.severity = LogMessageSeverity.Fatal
        of "PANIC":
          result.severity = LogMessageSeverity.Panic
        of "WARNING":
          result.severity = LogMessageSeverity.Warning
        of "NOTICE":
          result.severity = LogMessageSeverity.Notice
        of "DEBUG":
          result.severity = LogMessageSeverity.Debug
        of "LOG":
          result.severity = LogMessageSeverity.Log
        else: discard
      of 'C':
        result.code = currentMessage
      of 'M':
        result.message = currentMessage
      of 'D':
        result.detail = currentMessage
      of 'H':
        result.hint = currentMessage
      of 'P':
        try:
          let position = parseInt(currentMessage)
          result.position = position
        except:
          result.position = 0
      of 'q':
        result.internalQuery = currentMessage
      of 'W':
        result.where = currentMessage
      of 's':
        result.schema = currentMessage
      of 't':
        result.table = currentMessage
      of 'c':
        result.columnName = currentMessage
      of 'd':
        result.dataTypeName = currentMessage
      of 'n':
        result.constraintName = currentMessage
      of 'F':
        result.file = currentMessage
      of 'L':
        try:
          let line = parseInt(currentMessage)
          result.line = line
        except:
          result.line = 0
      of 'R':
        result.routine = currentMessage
      else: discard

proc parseErrorResponse(data: string): PostgresMessage {.inline.} =
  result = PostgresMessage(
    isBackend: true,
    backendMessageType: BackendMessageType.ErrorResponse,
    error: parseLogMessageFields(data)
  )

proc parseNoticeResponse(data: string): PostgresMessage {.inline.} =
  result = PostgresMessage(
    isBackend: true,
    backendMessageType: BackendMessageType.NoticeResponse,
    notice: parseLogMessageFields(data)
  )

proc parseAuthenticationRequest(data: string): PostgresMessage {.inline.} =
  var buff = initBuffer(data)
  let authenticationResponseType = buff.readInt32()

  result = PostgresMessage(
    isBackend: true,
    backendMessageType: BackendMessageType.AuthenticationRequest,
    authenticationType: AuthenticationType(authenticationResponseType)
  )

proc parseParameterStatus(data: string): PostgresMessage {.inline.} =
  var buff = initBuffer(data)
  let
    parameterName = buff.readString()
    parameterValue = buff.readString()

  result = PostgresMessage(
    isBackend: true,
    backendMessageType: BackendMessageType.ParameterStatus,
    parameterName: parameterName,
    parameterValue: parameterValue
  )

proc parseBackendKeyData(data: string): PostgresMessage {.inline.} =
  var buff = initBuffer(data)
  let
    backendProcessId: int32 = buff.readInt32()
    backendSecretKey: int32 = buff.readInt32()

  result = PostgresMessage(
    isBackend: true,
    backendMessageType: BackendMessageType.BackendKeyData,
    processId: backendProcessId,
    secretKey: backendSecretKey
  )

proc parseReadyForQuery(data: string): PostgresMessage {.inline.} =
  var transactionStatus: BackendTransactionStatus

  case data[0]
  of char(BackendTransactionStatus.InFailedTransactionBlock):
    transactionStatus = BackendTransactionStatus.InFailedTransactionBlock
  of char(BackendTransactionStatus.Idle):
    transactionStatus = BackendTransactionStatus.Idle
  of char(BackendTransactionStatus.InTransactionBlock):
    transactionStatus = BackendTransactionStatus.InTransactionBlock
  else:
    raise newException(PacketParseError, "Failed to parse ready for query packet. Unknown transaction status: " & $data[0])

  result = PostgresMessage(
    isBackend: true,
    backendMessageType: BackendMessageType.ReadyForQuery,
    backendTransactionStatus: transactionStatus
  )

proc parseCommandComplete(data: string): PostgresMessage {.inline.} =
  var buff = initBuffer(data)

  result = PostgresMessage(
    isBackend: true,
    backendMessageType: BackendMessageType.CommandComplete,
    commandTag: buff.readString()
  )

proc parseEmptyQueryResponse(): PostgresMessage {.inline.} =
  result = PostgresMessage(
    isBackend: true,
    backendMessageType: BackendMessageType.EmptyQueryResponse
  )

proc fromData*(typ: char, data: string): PostgresMessage =
  case typ
  of char(BackendMessageType.ErrorResponse):
    result = parseErrorResponse(data)
  of char(BackendMessageType.NoticeResponse):
    result = parseNoticeResponse(data)
  of char(BackendMessageType.AuthenticationRequest):
    result = parseAuthenticationRequest(data)
  of char(BackendMessageType.ParameterStatus):
    result = parseParameterStatus(data)
  of char(BackendMessageType.BackendKeyData):
    result = parseBackendKeyData(data)
  of char(BackendMessageType.ReadyForQuery):
    result = parseReadyForQuery(data)
  of char(BackendMessageType.CommandComplete):
    result = parseCommandComplete(data)
  of char(BackendMessageType.EmptyQueryResponse):
    result = parseEmptyQueryResponse()
  else:
    result = PostgresMessage(
      isBackend: true,
      backendMessageType: BackendMessageType.Unknown
    )
