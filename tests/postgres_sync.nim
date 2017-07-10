import postgres, unittest, terminal

suite "synchronous tests":
  proc handleNotice(notice: PostgresMessage) =
    styledWriteLine(stdout, fgYellow, "  [NOTICE] ", resetStyle, "[", notice.notice.code, "] ", notice.notice.message)

  let connection = open(user = "postgres", password = "password", database = "postgres", noticeCallback = handleNotice)
  connection.execute("CREATE TABLE IF NOT EXISTS users (id serial PRIMARY KEY, name varchar(255) NOT NULL, age integer NOT NULL);")

  test "insert with raw query":
    let affectedRows = connection.execute("INSERT INTO users (name, age) VALUES ('euan', 1);")
    check affectedRows == 1

  test "delete with raw query":
    let affectedRows = connection.execute("DELETE FROM users WHERE name = 'euan';")
    check affectedRows == 1
