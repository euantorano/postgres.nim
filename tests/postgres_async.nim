import postgres, unittest, asyncdispatch, terminal, os

suite "asynchronous tests":
  proc handleNotice(notice: PostgresMessage) =
    styledWriteLine(stdout, fgYellow, "  [NOTICE] ", resetStyle, "[", notice.notice.code, "] ", notice.notice.message)

  var host = getEnv("POSTGRES_HOST")
  if len(host) < 1:
    host = "localhost"

  let connection = waitFor openAsync(host = host, user = "postgres", password = "password", database = "postgres", noticeCallback = handleNotice)
  discard waitFor connection.execute("CREATE TABLE IF NOT EXISTS users (id serial PRIMARY KEY, name varchar(255) NOT NULL, age integer NOT NULL);")

  test "insert with raw query":
    let affectedRows = waitFor connection.execute("INSERT INTO users (name, age) VALUES ('euan', 1);")
    check affectedRows == 1

  test "delete with raw query":
    let affectedRows = waitFor connection.execute("DELETE FROM users WHERE name = 'euan';")
    check affectedRows == 1

  test "prepare statement":
    let prepared = waitFor connection.prepare("SELECT * FROM users;")
